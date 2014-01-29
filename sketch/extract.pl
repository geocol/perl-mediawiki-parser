use strict;
use warnings;
use Path::Class;
use Encode;
use MediaWikiXML::PageExtractor;

my $name = decode 'utf-8', shift;

my $cache_d = file (__FILE__)->dir->parent->parent->parent->subdir ('local', 'cache');
my $dump_f = $cache_d->file ('xml', 'jawiki-latest-pages-meta-current.xml');

my $mx = MediaWikiXML::PageExtractor->new_from_cache_d ($cache_d);
$mx->save_titles_from_f_if_necessary ($dump_f);

die "Not found" unless $mx->has_page_in_cached_titles ($name);

my $text = $mx->get_page_text_by_name_from_f_or_cache ($dump_f, $name);

die "Not found" unless defined $text;

print $text;
