use strict; # -*- Perl -*-
use warnings;
use Path::Class;
use Wanage::HTTP;
use Warabe::App;
use Web::DOM::Document;
use Text::MediaWiki::Parser;
use AnyEvent::MediaWiki::Source;

return sub {
  my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
  my $app = Warabe::App->new_from_http ($http);

  return $http->send_response (onready => sub {
    $app->execute (sub {
      my $path = $app->path_segments;

      if (length $path->[0] and
          defined $path->[1] and $path->[1] =~ /\A(?:text|xml)\z/ and
          not defined $path->[2]) {
        # /{lang}/{format}?name={page}
        my $name = $app->text_param ('name') // '';
        my $wp = AnyEvent::MediaWiki::Source->new_wikipedia_by_lang ($path->[0]);
        $wp->get_source_text_by_name_as_cv ($name)->cb (sub {
          my $text = $_[0]->recv;
          if (defined $text) {
            if ($path->[1] eq 'xml') {
              my $doc = new Web::DOM::Document;
              my $parser = Text::MediaWiki::Parser->new;
              $parser->parse_char_string ($text => $doc);
              $doc->title ($name);
              $app->http->set_response_header ('Content-Type' => 'text/xml; charset=utf-8');
              $app->http->send_response_body_as_text ($doc->inner_html);
              $app->http->close_response_body;
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
