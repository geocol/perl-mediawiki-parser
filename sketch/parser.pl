use strict;
use warnings;
use Path::Class;
use lib file (__FILE__)->dir->parent->subdir ('lib')->stringify;
use Encode;
use Web::DOM::Document;
use Text::MediaWiki::Parser;

local $/ = undef;
my $input = decode 'utf-8', <>;

my $doc = new Web::DOM::Document;
my $parser = Text::MediaWiki::Parser->new;
$parser->parse_char_string ($input => $doc);

print $doc->inner_html;
