use strict;
use warnings;
use Path::Class;
use lib glob file (__FILE__)->dir->parent->subdir ('t_deps', 'modules', '*', 'lib');
use Test::X1;
use Test::Differences;
use Test::HTCT::Parser;
use Text::MediaWiki::Parser;
use Web::DOM::Document;
use Web::HTML::Dumper qw(dumptree);

$Web::HTML::Dumper::NamespaceMapping->{q<http://suikawiki.org/n/mw>} = 'mw';

for my $file_name (glob file (__FILE__)->dir->parent->file ('t_deps', 'data', '*.dat')) {
  for_each_test $file_name, {data => {is_prefixed => 1},
                             document => {is_prefixed => 1}}, sub {
    my $test = shift;
    test {
      my $c = shift;
      my $doc = new Web::DOM::Document;
      my $parser = Text::MediaWiki::Parser->new;
      $parser->parse_char_string ($test->{data}->[0] => $doc);
      eq_or_diff dumptree $doc, $test->{document}->[0] . "\n";
      done $c;
    } n => 1, name => [$file_name, $test->{data}->[0]];
  };
}

run_tests;
