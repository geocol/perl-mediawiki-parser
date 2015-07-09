package AnyEvent::MediaWiki::Source;
use strict;
use warnings;
use AnyEvent;
use AnyEvent::Util qw(fork_call);
use URL::PercentEncode qw(percent_encode_c);
use JSON::Functions::XS qw(json_bytes2perl);
use Web::UserAgent::Functions qw(http_get);
use Web::HTML::Parser;
use Web::DOM::Document;

sub new_wikipedia_by_lang ($$) {
  return bless {top_url => 'https://' . $_[1] . '.wikipedia.org/'}, $_[0];
} # new_wikipedia_by_lang

sub new_wiktionary_by_lang ($$) {
  return bless {top_url => 'https://' . $_[1] . '.wiktionary.org/'}, $_[0];
} # new_wiktionary_by_lang

sub new_from_dump_f_and_cache_d ($$$) {
  return bless {dump_f => $_[1], cache_d => $_[2]}, $_[0];
} # new_from_dump_f_and_cache_d

sub top_url ($;$) {
  if (@_ > 1) {
    $_[0]->{top_url} = $_[1];
  }
  return $_[0]->{top_url};
} # top_url

sub get_source_text_by_name_as_cv ($$;%) {
  my ($self, $name, %args) = @_;
  if (defined $_[0]->{cache_d}) {
    $self->_get_source_text_by_name_as_cv_from_dump ($name, %args);
  } else {
    $self->_get_source_text_by_name_as_cv_by_http ($name, %args);
  }
} # get_source_text_by_name_as_cv

sub _get_source_text_by_name_as_cv_by_http ($$;%) {
  my ($self, $name, %args) = @_;
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

sub _get_source_text_by_name_as_cv_from_dump ($$;%) {
  my ($self, $name, %args) = @_;
  my $cv = AE::cv;
  my $dump_f = $self->{dump_f};
  my $cache_d = $self->{cache_d};

  fork_call {
    require MediaWikiXML::PageExtractor;
    my $mx = MediaWikiXML::PageExtractor->new_from_cache_d ($cache_d);
    $mx->save_titles_from_f_if_necessary ($dump_f);
    if (defined $args{ims}) {
      my $ts = $mx->has_page_in_cached_titles ($name);
      if (defined $ts and $ts <= $args{ims}) {
        return {not_modified => 1};
      } else {
        return {timestamp => $ts, # or undef
                data => $mx->get_page_text_by_name_from_f_or_cache ($dump_f, $name)}; # or undef
      }
    } else {
      return $mx->get_page_text_by_name_from_f_or_cache ($dump_f, $name); # or undef
    }
  } sub {
    if ($@) {
      warn $@;
      $cv->send (undef);
    } else {
      $cv->send ($_[0]);
    }
  };

  return $cv;
} # _get_source_text_by_name_as_cv_from_dump

sub get_category_members_by_http_as_cv ($$;%) {
  my ($self, $name, %args) = @_;
  my $url = $self->top_url;
  $url .= '/' unless $url =~ m{/\z};
  $url .= q<w/api.php>;

  my $cv = AE::cv;
  http_get
      url => $url,
      params => {
        action => 'query',
        list => 'categorymembers',
        cmtitle => $name,
        cmlimit => 500,
        format => 'json',
      },
      timeout => 100,
      anyevent => 1,
      cb => sub {
        my (undef, $res) = @_;
        unless ($res->is_success) {
          $cv->send (undef);
          return;
        }

        my $json = json_bytes2perl $res->content;
        $cv->send (eval { $json->{query}->{categorymembers} } || []);
      };
  return $cv;
} # get_category_members_by_http_as_cv

1;
