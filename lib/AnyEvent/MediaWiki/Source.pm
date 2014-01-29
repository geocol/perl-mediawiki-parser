package AnyEvent::MediaWiki::Source;
use strict;
use warnings;
use AnyEvent;
use AnyEvent::Util qw(fork_call);
use URL::PercentEncode qw(percent_encode_c);
use Web::UserAgent::Functions qw(http_get);
use Web::HTML::Parser;
use Web::DOM::Document;

sub new_wikipedia_by_lang ($$) {
  return bless {top_url => 'http://' . $_[1] . '.wikipedia.org/'}, $_[0];
} # new_wikipedia_by_lang

sub new_from_dump_f_and_cache_d ($$$) {
  return bless {dump_f => $_[1], cache_d => $_[2]}, $_[0];
} # new_from_dump_f_and_cache_d

sub top_url ($;$) {
  if (@_ > 1) {
    $_[0]->{top_url} = $_[1];
  }
  return $_[0]->{top_url};
} # top_url

sub get_source_text_by_name_as_cv ($$) {
  my ($self, $name) = @_;
  if (defined $_[0]->{cache_d}) {
    $self->_get_source_text_by_name_as_cv_from_dump ($name);
  } else {
    $self->_get_source_text_by_name_as_cv_by_http ($name);
  }
} # get_source_text_by_name_as_cv

sub _get_source_text_by_name_as_cv_by_http ($$) {
  my ($self, $name) = @_;
  my $url = $self->top_url;
  $url .= '/' unless $url =~ m{/\z};
  $url .= q<w/index.php?title=>.(percent_encode_c $name).q<&action=edit>,

  my $cv = AE::cv;
  http_get
      url => $url,
      timeout => 100,
      anyevent => 1,
      cb => sub {
        my (undef, $res) = @_;
        unless ($res->is_success) {
          $cv->send (undef);
          return;
        }

        my $parser = Web::HTML::Parser->new;
        my $doc = new Web::DOM::Document;
        $parser->parse_byte_string ('utf-8', $res->content => $doc);
        my $ta = $doc->get_elements_by_tag_name ('textarea')->[0];
        if (defined $ta) {
          my $text = $ta->default_value;
          $cv->send (length $text ? $text : undef);
        } else {
          $cv->send (undef);
        }
      };
  return $cv;
} # _get_source_text_by_name_as_cv_by_http

sub _get_source_text_by_name_as_cv_from_dump ($$) {
  my ($self, $name) = @_;
  my $cv = AE::cv;
  my $dump_f = $self->{dump_f};
  my $cache_d = $self->{cache_d};

  fork_call {
    require MediaWikiXML::PageExtractor;
    my $mx = MediaWikiXML::PageExtractor->new_from_cache_d ($cache_d);
    $mx->save_titles_from_f_if_necessary ($dump_f);

    return undef unless $mx->has_page_in_cached_titles ($name);
    return $mx->get_page_text_by_name_from_f_or_cache ($dump_f, $name); # or undef
  } sub {
    $cv->send ($_[0]);
  };

  return $cv;
} # _get_source_text_by_name_as_cv_from_dump

1;
