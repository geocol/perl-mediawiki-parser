package MediaWikiXML::PageExtractor;
use strict;
use warnings;
our $VERSION = '3.0';
use Path::Class;
require utf8;
use Encode;
use Web::DomainName::Punycode qw(encode_punycode);

sub new_from_cache_d ($$) {
  return bless {cache_d => $_[1]}, $_[0];
} # new_from_cache_d

## ------ Titles ------

sub cached_titles_f ($) {
  return $_[0]->{cached_titles_f} ||= $_[0]->{cache_d}->file ('titles.txt');
} # cached_titles_f

sub extract_titles_from_file ($$$) {
  my ($self, $file, $code) = @_;
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
      $code->(decode ('utf-8', $text));
    }
  }
} # extract_titles_from_file

sub save_titles_from_f ($$) {
  my ($self, $dump_f) = @_;
  my $dump_file = $dump_f->openr;
  my $out_file = $self->cached_titles_f->openw;
  MediaWikiXML::PageExtractor->extract_titles_from_file ($dump_file => sub {
    print $out_file encode ('utf8', $_[0]), "\x0A";
  });
} # save_titles_from_f

sub save_titles_from_f_if_necessary ($$) {
  my ($self, $dump_f) = @_;
  my $out_f = $self->cached_titles_f;
  return if -f $out_f and $out_f->stat->mtime > $dump_f->stat->mtime;
  return $self->save_titles_from_f ($dump_f);
} # save_titles_from_f_if_necessary

sub has_page_in_cached_titles ($$) {
  my ($self, $title) = @_;
  my $file = $self->cached_titles_f->openr;
  my $pattern = (encode 'utf8', $title) . "\x0A";
  while (<$file>) {
    if ($_ eq $pattern) {
      return 1;
    }
  }
  return 0;
} # has_page_in_cached_titles

## ------ Pages ------

sub cached_pages_d ($) {
  return $_[0]->{cached_pages_d} ||= $_[0]->{cache_d}->subdir ('pages');
} # cached_pages_d

sub get_page_xml_f_from_title ($$) {
  my ($self, $title) = @_;
  $title = decode ('utf-8', $title) unless utf8::is_utf8 ($title);
  $title = encode_punycode $title;
  $title =~ s{([^0-9A-Za-z])}{sprintf '_%02X', ord $1}ge;
  $title .= '.dat';
  return $self->cached_pages_d->file ($title);
} # get_page_xml_f_from_title

sub save_page_xml_from_f ($$$;%) {
  my ($self, $f => $title_pattern, %args) = @_;
  my $file = $f->openr;

  if (utf8::is_utf8 ($title_pattern . '')) {
    $title_pattern = encode ('utf8', $title_pattern);
    $title_pattern = qr/$title_pattern/;
  }
  
  $self->cached_pages_d->mkpath;
  
  my $count = 0;
  local $/ = '</page>';
  while (<$file>) {
    if (m[<title>([^<>]+)</title>]) {
      my $word = $1;
      if ($word =~ /$title_pattern/) {
        my $f = $self->get_page_xml_f_from_title ($word);
        #print STDERR "$word -> $f\n";
        eval {
          my $file = $f->openw;
          print $file $_;
          1;
        } or warn $@;
        return if $args{max} and $args{max} <= ++$count;
      }
    }
  }
} # save_page_xml_from_f

sub has_page_xml_in_cache ($$) {
  my ($self, $title) = @_;
  my $f = $self->get_page_xml_f_from_title ($title);
  return -f $f;
} # has_page_xml_in_cache

sub get_page_text_from_cache ($$;%) {
  my ($self, $title, %args) = @_;
  my $f = $self->get_page_xml_f_from_title ($title);
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
    return decode ('utf-8', $text);
  } else {
    return undef;
  }
} # get_page_text_from_cache

sub get_page_text_by_name_from_f_or_cache ($$$) {
  my ($self, $dump_f, $name) = @_;
  my $pattern = qr{\A\Q$name\E\z};
  my $cache_f = $self->get_page_xml_f_from_title ($name);
  if (-f $cache_f and $cache_f->stat->mtime > $dump_f->stat->mtime) {
    #
  } else {
    $self->save_page_xml_from_f ($dump_f, $pattern, max => 1);
  }
  return $self->get_page_text_from_cache ($name); # or undef
} # get_page_text_by_name_from_f_or_cache

1;

=head1 LICENSE

Copyright 2010 Wakaba <wakaba@suikawiki.org>.

Copyright 2014 Hatena <http://hatenacorp.jp/>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
