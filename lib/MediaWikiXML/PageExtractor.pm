package MediaWikiXML::PageExtractor;
use strict;
use warnings;
our $VERSION = '2.0';
use Path::Class;
require utf8;
use URL::PercentEncode;

our $RootD ||= file (__FILE__)->dir->parent->parent;
our $DataD ||= $RootD->subdir ('local')->subdir ('cache')->subdir ('page-by-name');

sub get_f_from_title ($$) {
  my ($class, $title) = @_;
  if (utf8::is_utf8 ($title)) {
    require Encode;
    $title = Encode::encode ('utf8', $title);
  }
  my $file_name = percent_encode_b $title;
  $file_name =~ s/_/_5F/g;
  $file_name =~ s/%/_/g;
  $file_name .= '.dat';
  return $DataD->file ($file_name);
} # get_f_from_title

sub has_text_in_cache ($$) {
  my ($class, $title) = @_;
  my $f = $class->get_f_from_title ($title);
  return -f $f;
} # has_text_in_cache

sub save_page_xml ($$$;%) {
  my ($class, $file => $title_pattern, %args) = @_;

  if (utf8::is_utf8 ($title_pattern . '')) {
    require Encode;
    $title_pattern = Encode::encode ('utf8', $title_pattern);
    $title_pattern = qr/$title_pattern/;
  }
  
  $DataD->mkpath;
  
  my $count = 0;
  local $/ = '</page>';
  while (<$file>) {
    if (m[<title>([^<>]+)</title>]) {
      my $word = $1;
      if ($word =~ /$title_pattern/) {
        my $f = $class->get_f_from_title ($word);
        print STDERR "$word -> $f\n";
        eval {
          my $file = $f->openw;
          print $file $_;
          1;
        } or warn $@;
        return if $args{max} and $args{max} <= ++$count;
      }
    }
  }
} # save_page_xml

sub extract_titles_from_file ($$$) {
  my ($class, $file, $code) = @_;
  local $/ = '</page>';
  my @list;
  require Encode;
  while (<$file>) {
    if (m[<title>([^<>]+)</title>]) {
      my $text = $1;
      $text =~ s/&lt;/</g;
      $text =~ s/&gt;/>/g;
      $text =~ s/&quot;/\x22/g;
      $text =~ s/&amp;/&/g;
      $code->(Encode::decode ('utf-8', $text));
    }
  }
} # extract_titles_from_file

sub get_text_from_cache ($$;%) {
  my ($class, $title, %args) = @_;
  my $f = $class->get_f_from_title ($title);
  if ($args{allow_not_found} and not -f $f) {
    return undef;
  }
  my $content = $f->slurp or return undef;
  if ($content =~ m[<text[^<>]*>(.*?)</text>]s) {
    my $text = $1;
    $text =~ s/&lt;/</g;
    $text =~ s/&gt;/>/g;
    $text =~ s/&quot;/\x22/g;
    $text =~ s/&amp;/&/g;
    require Encode;
    return Encode::decode ('utf-8', $text);
  } else {
    return undef;
  }
} # get_text_from_cache

1;

=head1 LICENSE

Copyright 2010 Wakaba <wakaba@suikawiki.org>.

Copyright 2014 Hatena <http://hatenacorp.jp/>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
