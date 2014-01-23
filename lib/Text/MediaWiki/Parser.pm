package Text::MediaWiki::Parser;
use strict;
use warnings;

sub MWNS () { 'http://suika.suikawiki.org/~wakaba/wiki/sw/n/MediaWiki' }

my $CanContainPhrasing = {
  p => 1, b => 1, i => 1, a => 1,
  s => 1, strike => 1,
  ref => 1, gallery => 1, nowiki => 1,
  block => 1, link => 1,
};

sub new ($) {
  return bless {}, $_[0];
} # new

sub parse_char_string ($$$) {
  my ($self, $data => $doc) = @_;

  $doc->inner_html ('<html xmlns="http://www.w3.org/1999/xhtml" xmlns:mw="'.MWNS.'"><head></head><body></body></html>');

  my @open = ($doc->body);
  $doc->body->set_user_data (level => 1);
  my $nowiki;

  my $insert_p = sub () {
    if (not $CanContainPhrasing->{$open[-1]->local_name}) {
      my $el = $doc->create_element ('p');
      $open[-1]->append_child ($el);
      push @open, $el;
    }
  };

  my $parse_inline = sub ($) {
    my $data = $_[0];

    while (length $data) {
      if ($nowiki) {
        if ($data =~ s{^</nowiki>}{}) {
          pop @open;
          $nowiki = 0;
        } elsif ($data =~ s{^([^<]+)}{} or $data =~ s{^(.)}{}s) {
          $open[-1]->manakai_append_text ($1);
        }
      } elsif ($data =~ s/^\{\{//) {
            my $el = $doc->create_element_ns (MWNS, 'mw:block');
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
            my $el = $doc->create_element_ns (MWNS, 'mw:link');
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
      } elsif ($data =~ s/^<(s|strike)>//) {
        $insert_p->();
        my $el = $doc->create_element ($1);
        $open[-1]->append_child ($el);
        push @open, $el;
      } elsif ($data =~ s{^</(s|strike)>}{}) {
        if ($open[-1]->local_name eq $1) {
          pop @open;
        } else {
          $insert_p->();
          $open[-1]->manakai_append_text ("</$1>");
        }
      } elsif ($data =~ s/^<(ref|gallery)>//) {
            $insert_p->() if $1 eq 'ref';
            my $el = $doc->create_element_ns (MWNS, 'mw:'.$1);
            $open[-1]->append_child ($el);
            push @open, $el;
        } elsif ($data =~ s{^</(ref|gallery)>}{}) {
            if ($open[-1]->local_name eq $1) {
                pop @open;
            } else {
                $insert_p->();
                $open[-1]->manakai_append_text ("</$1>");
            }
      } elsif ($data =~ s{^<nowiki>}{}) {
        my $el = $doc->create_element_ns (MWNS, 'mw:nowiki');
        $open[-1]->append_child ($el);
        push @open, $el;
        $nowiki = 1;
      } elsif ($data =~ s{^<(nowiki|references)\s*/>}{}) {
        my $el = $doc->create_element_ns (MWNS, 'mw:'.$1);
        $open[-1]->append_child ($el);
      } elsif ($data =~ s{^''}{}) {
            my $ln = $open[-1]->local_name;
            if ($ln eq 'b') {
                if ($data =~ s{^'}{}) {
                    pop @open;
                } else {
                    my $el = $doc->create_element ('i');
                    $open[-1]->append_child ($el);
                    push @open, $el
                }
            } elsif ($ln eq 'i') {
                pop @open;
            } else {
                $insert_p->();
                if ($data =~ s{^'}{}) {
                    my $el = $doc->create_element ('b');
                    $open[-1]->append_child ($el);
                    push @open, $el
                } else {
                    my $el = $doc->create_element ('i');
                    $open[-1]->append_child ($el);
                    push @open, $el
                }
            }
        } elsif ($data =~ s/^([^'<\{\}\[\]\x0A]+)// or $data =~ s/^(.)//s) {
            $insert_p->() unless $1 eq "\x0A";
            $open[-1]->manakai_append_text ($1)
                if $1 ne "\x0A" or
                   $CanContainPhrasing->{$open[-1]->local_name};
        }
    }
  };

  $data =~ s/\x0D\x0A/\x0A/g;
  $data =~ tr/\x0D/\x0A/;
  if ($data =~ s/^#REDIRECT\s*\[\[([^\[\]]+)\]\]\s*$//) {
    $doc->document_element->set_attribute_ns (MWNS, 'mw:redirect' => $1);
  }

  for my $line (split /\x0A/, $data) {
    if ($line =~ /^(={2,6})\s*(.+?)\s*\1$/) {
      my $level = length $1;
      my $text = $2;
      pop @open while not ({body => 1, section => 1}->{$open[-1]->local_name} and
                           $open[-1]->get_user_data ('level') < $level);
      my $next_level = $open[-1]->get_user_data ('level');
      $next_level++;
      while ($next_level < $level) {
        my $el = $doc->create_element ('section');
        $el->set_user_data (level => $next_level);
        $open[-1]->append_child ($el);
        push @open, $el;
        $next_level++;
      }

      my $el0 = $doc->create_element ('section');
      $el0->set_user_data (level => $level);
      my $el = $doc->create_element ('h1');
      $el0->append_child ($el);
      $el->manakai_append_text ($text);
      $open[-1]->append_child ($el0);
      push @open, $el0;
    } elsif ($line =~ /^----$/) {
      pop @open while not {body => 1, section => 1}->{$open[-1]->local_name};
      $open[-1]->append_child ($doc->create_element ('hr'));
    } elsif ($line =~ /^$/) {
      pop @open while not {body => 1, section => 1}->{$open[-1]->local_name};
    } else {
      $parse_inline->("\x0A" . $line);
    }
  }
} # parse_char_string

1;
