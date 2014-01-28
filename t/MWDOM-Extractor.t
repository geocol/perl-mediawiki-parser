use strict;
use warnings;
use Path::Class;
use lib glob file (__FILE__)->dir->parent->subdir ('t_deps', 'modules', '*', 'lib');
use Test::More;
use Test::X1;
use Text::MediaWiki::Parser;
use Web::DOM::Document;
use MWDOM::Extractor;

sub d ($) {
  my $p = Text::MediaWiki::Parser->new;
  my $doc = new Web::DOM::Document;
  $p->parse_char_string ($_[0] => $doc);
  return $doc;
}

test {
  my $c = shift;
  my $doc = d q{#REDIRECT [[abc def]]};
  my $x = MWDOM::Extractor->new_from_document ($doc);
  my $r = $x->redirect_wref;
  isa_ok $r, 'MWDOM::WRef';
  is $r->name, 'abc def';
  is $r->section, undef;
  done $c;
} n => 3, name => 'redirect';

test {
  my $c = shift;
  my $doc = d q{#REDIRECT [[abc def#ho ges]]};
  my $x = MWDOM::Extractor->new_from_document ($doc);
  my $r = $x->redirect_wref;
  isa_ok $r, 'MWDOM::WRef';
  is $r->name, 'abc def';
  is $r->section, 'ho ges';
  done $c;
} n => 3, name => 'redirect section';

for my $test (
  [q{hogehoge fuga
abc
def

aaa bbbb} => q{hogehoge fuga
abc
def}],
  [q{hogehoge fu[[ga]] http://a/b/c
abc
def

aaa bbbb} => q{hogehoge fuga http://a/b/c
abc
def}],
  [q{[[File:hoge.png|thumb]]
hogehoge fuga
abc
def

aaa bbbb} => q{hogehoge fuga
abc
def}],
) {
  test {
    my $c = shift;
    my $doc = d $test->[0];
    my $x = MWDOM::Extractor->new_from_document ($doc);
    is $x->abstract_text, $test->[1];
    done $c;
  } n => 1, name => 'abstract';
}

run_tests;
