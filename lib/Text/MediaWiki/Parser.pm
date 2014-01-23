package Text::MediaWiki::Parser;
use strict;
use warnings;

sub MWNS () { 'http://suika.suikawiki.org/~wakaba/wiki/sw/n/MediaWiki' }

my $HTMLPhrasing = {
  s => 1, strike => 1, ins => 1, u => 1, del => 1, code => 1, tt => 1,
  span => 1, font => 1,
};

my $HTMLFlow = {
  div => 1, blockquote => 1,
};

my $HTMLPhrasingPattern = join '|', keys %$HTMLPhrasing;
my $HTMLFlowPattern = join '|', keys %$HTMLFlow;

my $CanContainPhrasing = {
  %$HTMLPhrasing,
  p => 1, b => 1, i => 1, a => 1, pre => 1,
  li => 1, dt => 1, dd => 1,
  ref => 1, gallery => 1, nowiki => 1,
  block => 1, link => 1, comment => 1,
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
  my $current_tag;

  my $html = $doc->implementation->create_document->create_element ('div');
  $html->owner_document->manakai_is_html (1);

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
      if (defined $nowiki) {
        if ($data =~ s{^(.*?)$nowiki}{}s) {
          $open[-1]->manakai_append_text ($1);
          pop @open;
          undef $nowiki;
        } else {
          $open[-1]->manakai_append_text ($data);
          $data = '';
        }
        next;
      } elsif (defined $current_tag) {
        $data = $current_tag . $data;
        undef $current_tag;
      }

      if ($data =~ s/^\{\{//) {
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
      } elsif ($data =~ s/^<($HTMLPhrasingPattern)\b((?>[^>"']|"[^"]*"|'[^']*')*)>//o) {
        $insert_p->();
        my $el = $doc->create_element ($1);
        if (length $2) {
          $html->inner_html ('<div ' . $2 . '></div>');
          for (@{$html->first_child->attributes}) {
            $el->set_attribute ($_->name => $_->value);
          }
        }
        $open[-1]->append_child ($el);
        push @open, $el;
      } elsif ($data =~ s/^<($HTMLFlowPattern)\b((?>[^>"']|"[^"]*"|'[^']*')*)>//o) {
        pop @open while not {body => 1, section => 1, li => 1, dt => 1, dd => 1, %$HTMLFlow}->{$open[-1]->local_name};
        my $el = $doc->create_element ($1);
        if (length $2) {
          $html->inner_html ('<div ' . $2 . '></div>');
          for (@{$html->first_child->attributes}) {
            $el->set_attribute ($_->name => $_->value);
          }
        }
        $open[-1]->append_child ($el);
        push @open, $el;
      } elsif ($data =~ s{^(</($HTMLPhrasingPattern)\s*>)}{}o) {
        if ($open[-1]->local_name eq $2) {
          pop @open;
        } else {
          $insert_p->();
          $open[-1]->manakai_append_text ($1);
        }
      } elsif ($data =~ s{^(</($HTMLFlowPattern)\s*>)}{}o) {
        if ($open[-1]->local_name eq $2) {
          pop @open;
        } elsif ($open[-1]->local_name eq 'p' and
                 $open[-2]->local_name eq $2) {
          pop @open;
          pop @open;
        } else {
          $insert_p->();
          $open[-1]->manakai_append_text ($1);
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
        $insert_p->();
        my $el = $doc->create_element_ns (MWNS, 'mw:nowiki');
        $open[-1]->append_child ($el);
        push @open, $el;
        $nowiki = qr{</nowiki\s*>};
      } elsif ($data =~ s{^<pre\b((?>[^>"']|"[^"]*"|'[^']*')*)>}{}) {
        pop @open while not {body => 1, section => 1, li => 1, dt => 1, dd => 1, %$HTMLFlow}->{$open[-1]->local_name};
        my $el = $doc->create_element ('pre');
        if (length $1) {
          $html->inner_html ('<div ' . $1 . '></div>');
          for (@{$html->first_child->attributes}) {
            $el->set_attribute ($_->name => $_->value);
          }
        }
        $el->set_attribute_ns (MWNS, 'mw:nowiki' => '');
        $open[-1]->append_child ($el);
        push @open, $el;
        $nowiki = qr{</pre\s*>};
      } elsif ($data =~ s{^<br\s*/?>}{}) {
        $insert_p->();
        my $el = $doc->create_element ('br');
        $open[-1]->append_child ($el);
      } elsif ($data =~ s{^<(nowiki|references)\s*/>}{}) {
        my $el = $doc->create_element_ns (MWNS, 'mw:'.$1);
        $open[-1]->append_child ($el);
      } elsif ($data =~ s{^(<[a-z0-9]+\b(?>[^>"']|"[^"]*"|'[^']*')*)$}{}) {
        $current_tag = $1;
      } elsif ($data =~ s{^<!--}{}) {
        my $el = $doc->create_element_ns (MWNS, 'mw:comment');
        $open[-1]->append_child ($el);
        push @open, $el;
        $nowiki = qr{-->};
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
    if (defined $nowiki or defined $current_tag) {
      $parse_inline->("\x0A" . $line);
    } elsif ($line =~ /^(={2,6})\s*(.+?)\s*\1$/s) {
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
    } elsif ($line =~ /^([*#:;]+)\s*(.+)$/s) {
      my $level = length $1;
      my $text = $2;
      my $list_type = {'*' => 'ul', '#' => 'ol',
                       ':' => 'dl', ';' => 'dl'}->{substr $1, -1};
      my $item_type = {'*' => 'li', '#' => 'li',
                       ':' => 'dd', ';' => 'dt'}->{substr $1, -1};

      pop @open while not (({li => 1, dt => 1, dd => 1}->{$open[-1]->local_name} and
                            $open[-1]->get_user_data ('level') <= $level) or
                           {body => 1, section => 1}->{$open[-1]->local_name});
      if ({li => 1, dt => 1, dd => 1}->{$open[-1]->local_name} and
          $open[-1]->get_user_data ('level') == $level) {
        pop @open;
        unless ($open[-1]->local_name eq $list_type) {
          pop @open;
          my $el = $doc->create_element ($list_type);
          $open[-1]->append_child ($el);
          push @open, $el;
        }
        my $el = $doc->create_element ($item_type);
        $el->set_user_data (level => $level);
        $open[-1]->append_child ($el);
        push @open, $el;
      }
      my $next_level = {li => 1, dt => 1, dd => 1}->{$open[-1]->local_name}
          ? $open[-1]->get_user_data ('level') + 1 : 1;
      while (not ({li => 1, dt => 1, dd => 1}->{$open[-1]->local_name} and
                  $open[-1]->get_user_data ('level') == $level)) {
        my $el0 = $doc->create_element ($list_type);
        my $el = $doc->create_element ($item_type);
        $el0->append_child ($el);
        $el->set_user_data (level => $next_level);
        $open[-1]->append_child ($el0);
        push @open, $el0, $el;
        $next_level++;
      }
      $parse_inline->($text);
    } elsif ($line =~ /^ <nowiki>(.*)$/s) {
      my $text = $1;
      pop @open while not {body => 1, section => 1}->{$open[-1]->local_name};
      my $el = $doc->create_element_ns (MWNS, 'mw:nowiki');
      $el->set_attribute (pre => '');
      $open[-1]->append_child ($el);
      push @open, $el;
      $nowiki = qr{</nowiki\s*>};
      $parse_inline->($text);
    } elsif ($line =~ /^ .*$/s) {
      pop @open while not {body => 1, section => 1, pre => 1}->{$open[-1]->local_name};
      unless ($open[-1]->local_name eq 'pre') {
        my $el = $doc->create_element ('pre');
        $open[-1]->append_child ($el);
        push @open, $el;
        $parse_inline->(substr $line, 1);
      } else {
        $parse_inline->("\x0A" . substr $line, 1);
      }
    } elsif ($line =~ /^----$/) {
      pop @open while not {body => 1, section => 1}->{$open[-1]->local_name};
      $open[-1]->append_child ($doc->create_element ('hr'));
    } elsif ($line =~ /^$/) {
      pop @open while not {body => 1, section => 1}->{$open[-1]->local_name};
    } else {
      if ({li => 1, dt => 1, dd => 1, pre => 1}->{$open[-1]->local_name}) {
        pop @open while not {body => 1, section => 1}->{$open[-1]->local_name};
      }
      $parse_inline->("\x0A" . $line);
    }
  }
} # parse_char_string

1;
