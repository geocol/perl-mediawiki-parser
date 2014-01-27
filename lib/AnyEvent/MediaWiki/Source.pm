package AnyEvent::MediaWiki::Source;
use strict;
use warnings;
use AnyEvent;
use URL::PercentEncode qw(percent_encode_c);
use Web::UserAgent::Functions qw(http_get);
use Web::HTML::Parser;
use Web::DOM::Document;

sub new ($) {
  return bless {}, $_[0];
} # new

sub new_wikipedia_by_lang ($$) {
  my $self = $_[0]->new;
  $self->top_url ('http://' . $_[1] . '.wikipedia.org/');
  return $self;
} # new_wikipedia_by_lang

sub top_url ($;$) {
  if (@_ > 1) {
    $_[0]->{top_url} = $_[1];
  }
  return $_[0]->{top_url};
} # top_url

sub get_source_text_by_name_as_cv ($$) {
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
} # get_source_text_by_name

1;
