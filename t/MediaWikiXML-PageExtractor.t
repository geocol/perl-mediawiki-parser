use strict;
use warnings;
use Path::Class;
use lib file (__FILE__)->dir->parent->subdir ('lib')->stringify;
use lib glob file (__FILE__)->dir->parent->subdir ('t_deps/modules/*/lib');
use MediaWikiXML::PageExtractor;
use Test::More;
use Test::X1;

my $cache_d = file (__FILE__)->dir->subdir ('cache-yummy');

for my $test (
  ['abc', 'pages/abc_2D.dat'],
  ["\x{5000}\x{5001}\x{5002}abc", 'pages/abc_2D7p0efg.dat'],
  ['a+*&<>*a"//bb=-~\\_', 'pages/a_2B_2A_26_3C_3E_2Aa_22_2F_2Fbb_3D_2D_7E_5C_5F_2D.dat'],
  ["\xE5\x80\x80\xE5\x80\x81abc", 'pages/abc_2D7p0ef.dat'],
) {
  test {
    my $c = shift;
    my $f = MediaWikiXML::PageExtractor->new_from_cache_d ($cache_d)->get_page_xml_f_from_title ($test->[0]);
    isa_ok $f, 'Path::Class::File';
    is $f . '', $cache_d->file ($test->[1]) . '';
    done $c;
  } n => 2, name => 'get_f_from_title';
}

run_tests;

=head1 LICENSE

Copyright 2010-2014 Wakaba <wakaba@suikawiki.org>.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
