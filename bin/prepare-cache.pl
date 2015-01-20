use strict;
use warnings;
use Path::Class;
use MediaWikiXML::PageExtractor;

my $database = shift or die;

my $root_d = file (__FILE__)->dir->parent;

my $dump_f = $root_d->file ('local', 'wpserver', 'xml', $database . '.xml');
my $cache_d = $root_d->subdir ('local', 'wpserver', 'cache', $database);

my $mx = MediaWikiXML::PageExtractor->new_from_cache_d ($cache_d);
$mx->save_titles_from_f_if_necessary ($dump_f);
