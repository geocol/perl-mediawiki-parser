package Text::MediaWiki::Parser;
use strict;
use warnings;

sub MWNS () { 'http://temp.test/' }

my $CanContainPhrasing = {
  p => 1, strong => 1, em => 1, a => 1,
  ref => 1, gallery => 1,
  block => 1, link => 1,
};

sub new ($) {
  return bless {}, $_[0];
} # new

sub parse_char_string ($$$) {
  my ($self, $data => $doc) = @_;

  $data =~ s/\x0D\x0A/\x0A/g;
  $data =~ tr/\x0D/\x0A/;

  $doc->inner_html ('<html xmlns="http://www.w3.org/1999/xhtml"><head></head><body></body></html>');

  my @open = ($doc->body);

  my $insert_p = sub () {
    if (not $CanContainPhrasing->{$open[-1]->local_name}) {
      my $el = $doc->create_element ('p');
      $open[-1]->append_child ($el);
      push @open, $el;
    }
  };

  if ($data =~ s/^#REDIRECT\s*\[\[([^\[\]]+)\]\]\s*$//) {
    $doc->document_element->set_attribute_ns (MWNS, 'mw:redirect' => $1);
  }

    while (length $data) {
        if ($data =~ s/^\{\{//) {
            my $el = $doc->create_element_ns (MWNS, 'block');
            $open[-1]->append_child ($el);
            push @open, $el;
        } elsif ($data =~ s/^\}\}//) {
            if ($open[-1]->local_name eq 'block') {
                pop @open;
            } else {
                $insert_p->();
                $open[-1]->manakai_append_text ('}}');
            }
        } elsif ($data =~ s/^\[\[//) {
            $insert_p->();
            my $el = $doc->create_element_ns (MWNS, 'link');
            $open[-1]->append_child ($el);
            push @open, $el;
        } elsif ($data =~ s/^\]\]//) {
            if ($open[-1]->local_name eq 'link') {
                pop @open;
            } else {
                $insert_p->();
                $open[-1]->manakai_append_text (']]');
            }
        } elsif ($data =~ s/^\[(http:[^\s\]]+)\s*//) {
            $insert_p->();
            my $el = $doc->create_element ('a');
            $el->set_attribute (href => $1);
            $open[-1]->append_child ($el);
            push @open, $el;
        } elsif ($data =~ s/^\]//) {
            if ($open[-1]->local_name eq 'a') {
                pop @open;
            } else {
                $insert_p->();
                $open[-1]->manakai_append_text (']');
            }
        } elsif ($data =~ s/^<(ref|gallery)>//) {
            $insert_p->() if $1 eq 'ref';
            my $el = $doc->create_element_ns (MWNS, $1);
            $open[-1]->append_child ($el);
            push @open, $el;
        } elsif ($data =~ s{^</(ref|gallery)>}{}) {
            if ($open[-1]->local_name eq $1) {
                pop @open;
            } else {
                $insert_p->();
                $open[-1]->manakai_append_text ("</$1>");
            }
        } elsif ($data =~ s{^<(references)\s*/>}{}) {
            my $el = $doc->create_element_ns (MWNS, $1);
            $open[-1]->append_child ($el);
        } elsif ($data =~ s{^''}{}) {
            my $ln = $open[-1]->local_name;
            if ($ln eq 'strong') {
                if ($data =~ s{^'}{}) {
                    pop @open;
                } else {
                    my $el = $doc->create_element ('em');
                    $open[-1]->append_child ($el);
                    push @open, $el
                }
            } elsif ($ln eq 'em') {
                pop @open;
            } else {
                $insert_p->();
                if ($data =~ s{^'}{}) {
                    my $el = $doc->create_element ('strong');
                    $open[-1]->append_child ($el);
                    push @open, $el
                } else {
                    my $el = $doc->create_element ('em');
                    $open[-1]->append_child ($el);
                    push @open, $el
                }
            }
        } elsif ($data =~ s/^\x0A==\s*(.+?)\s*==\x0A//) {
            pop @open if $open[-1]->local_name eq 'p';
            if ($open[-1]->local_name eq 'section') {
                pop @open;
            }
            my $el0 = $doc->create_element ('section');
            my $el = $doc->create_element ('h1');
            $el0->append_child ($el);
            $el->manakai_append_text ($1);
            $open[-1]->append_child ($el0);
            push @open, $el0;
        } elsif ($data =~ s/^\x0A\x0A+//) {
            pop @open if $open[-1]->local_name eq 'p';
            $data = "\x0A" . $data;
        } elsif ($data =~ s/^([^'<\{\}\[\]\x0A]+)// or $data =~ s/^(.)//s) {
            $insert_p->() unless $1 eq "\x0A";
            $open[-1]->manakai_append_text ($1);
        }
    }
} # parse_char_string

1;
