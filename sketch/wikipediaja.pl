use strict;
use warnings;
use Path::Class;
use lib file (__FILE__)->dir->parent->subdir ('lib')->stringify;
use Encode;
use AnyEvent;
use AnyEvent::MediaWiki::Source;
use Text::MediaWiki::Parser;

my $cv = AE::cv;

my $word = decode 'utf-8', shift;

my $mw = AnyEvent::MediaWiki::Source->new_wikipedia_by_lang ('ja');
$mw->get_source_text_by_name_as_cv ($word)->cb (sub {
  my $data = $_[0]->recv;
  if (defined $data) {
    my $doc = new Web::DOM::Document;
    my $parser = Text::MediaWiki::Parser->new;
    $parser->parse_char_string ($data => $doc);
    $doc->title ($word);
    
    print $doc->inner_html;

    use MWDOM::Extractor;
    use JSON::Functions::XS qw(perl2json_bytes_for_record);
    my $x = MWDOM::Extractor->new_from_document ($doc);
    print perl2json_bytes_for_record +{redirect => {%{$x->redirect_wref or {}}},
                                       abstract => $x->abstract_text};

    $cv->send;
  } else {
    die "Page not found\n";
  }
});

$cv->recv;
