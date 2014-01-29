# -*- Perl -*-
use strict;
use warnings;
use Path::Class;
use URL::PercentEncode qw(percent_encode_c);
use JSON::Functions::XS qw(file2perl);
use Wanage::HTTP;
use Warabe::App;
use Web::DOM::Document;
use Text::MediaWiki::Parser;
use AnyEvent::MediaWiki::Source;
use MWDOM::Extractor;

my $KeyMapping = {};
if (defined $ENV{WPSERVER_KEY_MAPPING}) {
  my $f = file ($ENV{WPSERVER_KEY_MAPPING});
  my $base_d = $f->dir;
  my $json = file2perl $f || {};
  if (ref $json eq 'HASH') {
    for (keys %$json) {
      if (ref $json->{$_} eq 'HASH') {
        $KeyMapping->{$_} = {cache_d => dir ($json->{$_}->{cache_dir_name})->absolute ($base_d),
                             dump_f => file ($json->{$_}->{dump_file_name})->absolute ($base_d)};
      }
    }
  }
}

sub _parse ($$) {
  my $doc = new Web::DOM::Document;
  my $parser = Text::MediaWiki::Parser->new;
  $parser->parse_char_string ($_[1] => $doc);
  $doc->title ($_[0]);
  return $doc;
} # _parse

sub _url ($$) {
  return join '',
      (map { '/' . percent_encode_c $_ } @{$_[0]}),
      '?',
      'name=' . percent_encode_c $_[1];
} # _url

sub _name ($) {
  my $s = shift;
  $s =~ s/\A\s+//;
  $s =~ s/\s+\z//;
  $s =~ s/\s+/_/;
  $s =~ s/^([a-z])/uc $1/ge;
  $s =~ s/(_[a-z])/uc $1/ge;
  return $s;
} # _name

sub _wp ($) {
  my $wiki_key = $_[0];

  if ($KeyMapping->{$wiki_key}) {
    return AnyEvent::MediaWiki::Source->new_from_dump_f_and_cache_d
        ($KeyMapping->{$wiki_key}->{dump_f},
         $KeyMapping->{$wiki_key}->{cache_d});
  } else {
    return AnyEvent::MediaWiki::Source->new_wikipedia_by_lang ($wiki_key);
  }
} # _wp

return sub {
  my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
  my $app = Warabe::App->new_from_http ($http);

  return $http->send_response (onready => sub {
    $app->execute (sub {
      my $path = $app->path_segments;

      if (length $path->[0] and
          defined $path->[1] and $path->[1] =~ /\A(?:text|xml|abstract)\z/ and
          not defined $path->[2]) {
        # /{wikikey}/{format}?name={page}
        my $name = _name $app->text_param ('name') // '';
        my $wp = _wp $path->[0] or $app->throw_error (404);
        $wp->get_source_text_by_name_as_cv ($name)->cb (sub {
          my $text = $_[0]->recv;
          if (defined $text) {
            if ($path->[1] eq 'xml') {
              my $doc = _parse $name, $text;
              $app->http->set_response_header ('Content-Type' => 'text/xml; charset=utf-8');
              $app->http->send_response_body_as_text ($doc->inner_html);
              $app->http->close_response_body;
            } elsif ($path->[1] eq 'abstract') {
              my $doc = _parse $name, $text;
              my $x = MWDOM::Extractor->new_from_document ($doc);
              my $r = $x->redirect_wref;
              if (defined $r) {
                $app->send_redirect (_url [$path->[0], $path->[1]], $r->name);
              } else {
                $app->send_plain_text ($x->abstract_text // '');
              }
            } else {
              $app->send_plain_text ($text);
            }
          } else {
            $app->send_error (404);
          }
        });
        return $app->throw;
      }

      return $app->throw_error (404);
    });
  });
};
