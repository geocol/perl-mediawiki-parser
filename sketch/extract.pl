use strict;
use warnings;
use Path::Class;
use Encode;
use MediaWikiXML::PageExtractor;

my $name = shift;
my $pattern = qr/^\Q$name\E$/;

my $f = file (__FILE__)->dir->parent->parent->parent->file ('local', 'cache', 'xml', 'jawiki-latest-pages-meta-current.xml');

my $index_f = file (__FILE__)->dir->parent->parent->parent->file ('local', 'cache', 'titles.txt');
unless (-f $index_f) {
  my $file = $f->openr;
  my $out = $index_f->openw;
  MediaWikiXML::PageExtractor->extract_titles_from_file ($file => sub {
    print $out encode ('utf-8', $_[0]), "\n";
  });
}

{
    warn "reading titles...\n";
    my @list = ($index_f->slurp);
    warn "done\n";
    sub has_page ($) {
        my $name = $_[0];
        for (@list) {
            if ($_ eq $name . "\x0A") {
                return 1;
            }
        }
        return 0;
    }
}

die "Not found" unless has_page $name;

my $file = $f->openr;
MediaWikiXML::PageExtractor->save_page_xml ($file, $pattern, max => 1)
    unless MediaWikiXML::PageExtractor->has_text_in_cache ($name);

my $text = MediaWikiXML::PageExtractor->get_text_from_cache ($name);

die "Not found" unless defined $text;

print $text;
