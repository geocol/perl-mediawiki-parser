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
  ul => 1, ol => 1, li => 1, p => 1,
};

my $HTMLPhrasingPattern = join '|', keys %$HTMLPhrasing;
my $HTMLFlowPattern = join '|', keys %$HTMLFlow;

my $CanContainPhrasing = {
  %$HTMLPhrasing,
  p => 1, b => 1, i => 1, a => 1, pre => 1,
  li => 1, dt => 1, dd => 1,
  ref => 1, gallery => 1, nowiki => 1,
  block => 1, l => 1, wref => 1, xl => 1, href => 1, comment => 1,
  ul => 1, ol => 1, dl => 1,
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

  my $set_attrs = sub {
    my ($attrs => $el) = @_;
    if (length $attrs) {
      $attrs =~ s/&(?:\x{05E8}\x{05DC}\x{05DE}|\x{0631}\x{0644}\x{0645});/&rlm;/g;
      $html->inner_html ('<div ' . $attrs . '></div>');
      for (@{$html->first_child->attributes}) {
        $el->set_attribute ($_->name => $_->value);
      }
    }
  };

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
        my $el = $doc->create_element_ns (MWNS, 'mw:l');
        $el->set_attribute ('embed' => '') if $data =~ /^(?:File:|Image:)/;
        $open[-1]->append_child ($el);
        push @open, $el;
      } elsif ($data =~ s/^#REDIRECT\s*\[\[//) {
        $insert_p->();
        my $el = $doc->create_element_ns (MWNS, 'mw:l');
        $el->set_attribute (redirect => '');
        $open[-1]->append_child ($el);
        push @open, $el;
      } elsif ($data =~ s/^\]//) {
        if ($open[-1]->local_name eq 'l' and $data =~ s/^\]//) {
          if ($data =~ s/^([^\s\[<{'&#]+)//) {
            if ($open[-1]->has_attribute_ns (undef, 'wref') or
                ($open[-1]->children->length and
                 $open[-1]->children->[0]->local_name eq 'wref')) {
              $open[-1]->manakai_append_text ($1);
            } else {
              if ($open[-1]->children->length) {
                my $el = $doc->create_element_ns (MWNS, 'mw:wref');
                $el->append_child ($_->clone_node (1))
                    for ($open[-1]->child_nodes->to_list);
                $open[-1]->insert_before ($el, $open[-1]->first_child);
              } else {
                $open[-1]->set_attribute (wref => $open[-1]->text_content);
              }
              $open[-1]->manakai_append_text ($1);
            }
          }
          pop @open;
        } elsif ($open[-1]->local_name eq 'xl') {
          pop @open;
        } else {
          $insert_p->();
          $open[-1]->manakai_append_text (']');
        }
      } elsif ($data =~ s/^\[(?=[a-z]+:|\{\{)//) {
        $insert_p->();
        my $el = $doc->create_element_ns (MWNS, 'mw:xl');
        $open[-1]->append_child ($el);
        push @open, $el;
      } elsif ($data =~ s/^http://) {
        if ($open[-1]->local_name eq 'xl') {
          $open[-1]->manakai_append_text ('http:');
        } else {
          $insert_p->();
          my $el = $doc->create_element_ns (MWNS, 'mw:xl');
          $open[-1]->append_child ($el);
          push @open, $el;
          $open[-1]->set_attribute (bare => '');
          $open[-1]->manakai_append_text ('http:');
        }
      } elsif ($data =~ s/^<($HTMLPhrasingPattern)\b((?>[^>"']|"[^"]*"|'[^']*')*)>//o) {
        $insert_p->();
        my $el = $doc->create_element ($1);
        $set_attrs->($2 => $el);
        $open[-1]->append_child ($el);
        push @open, $el;
      } elsif ($data =~ s/^<($HTMLFlowPattern)\b((?>[^>"']|"[^"]*"|'[^']*')*)>//o) {
        pop @open while not {body => 1, section => 1, li => 1, dt => 1, dd => 1, %$HTMLFlow, p => 0}->{$open[-1]->local_name};
        my $el = $doc->create_element ($1);
        $set_attrs->($2 => $el);
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
      } elsif ($data =~ s/^<(gallery)\b((?>[^>"']|"[^"]*"|'[^']*')*)>//o) {
        pop @open while not {body => 1, section => 1, li => 1, dt => 1, dd => 1, %$HTMLFlow, p => 0}->{$open[-1]->local_name};
        my $el = $doc->create_element_ns (MWNS, 'mw:'.$1);
        $set_attrs->($2 => $el);
        $open[-1]->append_child ($el);
        push @open, $el;
        $data =~ s/^\s+//;
        if (length $data) {
          my $el = $doc->create_element_ns (MWNS, 'mw:l');
          $el->set_attribute (embed => '');
          $el->set_attribute (implied => '');
          $open[-1]->append_child ($el);
          push @open, $el;
        }
      } elsif ($data =~ s/^<(ref)>//) {
            $insert_p->() if $1 eq 'ref';
            my $el = $doc->create_element_ns (MWNS, 'mw:'.$1);
            $open[-1]->append_child ($el);
            push @open, $el;
        } elsif ($data =~ s{^</(ref)>}{}) {
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
        pop @open while not {body => 1, section => 1, li => 1, dt => 1, dd => 1, %$HTMLFlow, p => 0}->{$open[-1]->local_name};
        my $el = $doc->create_element ('pre');
        $set_attrs->($1 => $el);
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
      } elsif ($data =~ s/^(&[a-z0-9]+;)//) {
        $insert_p->();
        $html->inner_html ($1);
        $open[-1]->manakai_append_text ($html->text_content);
      } elsif ($data =~ s/^&(?:\x{05E8}\x{05DC}\x{05DE}|\x{0631}\x{0644}\x{0645});//) {
        $insert_p->();
        $open[-1]->manakai_append_text ("\x{200F}"); # RKM
      } elsif ($data =~ s/^\|//) {
        if ($open[-1]->local_name eq 'l') {
          if ($open[-1]->has_attribute_ns (undef, 'embed')) {
            if ($data =~ s/^(border|frameless|frame|thumb(?:nail)?)(?=\||\]\])//) {
            $open[-1]->set_attribute (format => $1);
              next;
            } elsif ($data =~ s/^([0-9]+)px(?=\||\]\]|\z)//) {
              $open[-1]->set_attribute (width => $1);
              next;
            } elsif ($data =~ s/^x([0-9]+)px(?=\||\]\]|\z)//) {
              $open[-1]->set_attribute (height => $1);
              next;
            } elsif ($data =~ s/^([0-9]+)x([0-9]+)px(?=\||\]\]|\z)//) {
              $open[-1]->set_attribute (width => $1);
              $open[-1]->set_attribute (height => $2);
              next;
            } elsif ($data =~ s/^(upright)(?=\||\]\]|\z)//) {
              $open[-1]->set_attribute (resizing => $1);
              next;
            } elsif ($data =~ s/^(left|right|center|none)(?=\||\]\]|\z)//) {
              $open[-1]->set_attribute (align => $1);
              next;
            } elsif ($data =~ s/^(sub|super|top|text-top|middle|bottom|text-bottom)(?=\||\]\]|\z)//) {
              $open[-1]->set_attribute (valign => $1);
              next;
            } elsif ($data =~ s/^(link|alt|page|class|lang|thumb)=([^|\]]*)(?=\||\]\]|\z)//) {
              $open[-1]->set_attribute ($1 => $2);
              $open[-1]->set_attribute (format => 'thumb') if $1 eq 'thumb';
              next;
            }
          }

          if ($open[-1]->has_attribute_ns (undef, 'wref') or
              ($open[-1]->children->length and
               $open[-1]->children->[0]->local_name eq 'wref')) {
            $insert_p->();
            $open[-1]->manakai_append_text ('|');
          } else {
            if ($open[-1]->children->length) {
              my $el = $doc->create_element_ns (MWNS, 'mw:wref');
              $el->append_child ($_) for ($open[-1]->child_nodes->to_list);
              $open[-1]->append_child ($el);
            } else {
              $open[-1]->set_attribute (wref => $open[-1]->text_content);
              $open[-1]->text_content ('');
            }
          }
        } else {
          $insert_p->();
          $open[-1]->manakai_append_text ('|');
        }
      } elsif ($data =~ s/^(\s)//) {
        if ($open[-1]->local_name eq 'xl') {
          if ($open[-1]->has_attribute ('bare')) {
            pop @open;
            #
          } elsif (($open[-1]->has_attribute_ns (undef, 'href') or
                   ($open[-1]->children->length and
                    $open[-1]->children->[0]->local_name eq 'href'))) {
            #
          } else {
            if ($open[-1]->children->length) {
              my $el = $doc->create_element_ns (MWNS, 'mw:href');
              $el->append_child ($_) for ($open[-1]->child_nodes->to_list);
              $open[-1]->append_child ($el);
            } else {
              $open[-1]->set_attribute (href => $open[-1]->text_content);
              $open[-1]->text_content ('');
            }
            $data =~ s/^\s+//;
            next;
          }
        }
        $insert_p->() unless $1 eq "\x0A";
        $open[-1]->manakai_append_text ($1)
            if $1 ne "\x0A" or
               $CanContainPhrasing->{$open[-1]->local_name};
      } elsif ($data =~ s/^([^&'<\{\}\[\]|#\s]+)// or $data =~ s/^(.)//s) {
        $insert_p->() unless $1 eq "\x0A";
        $open[-1]->manakai_append_text ($1)
            if $1 ne "\x0A" or
               $CanContainPhrasing->{$open[-1]->local_name};
      }
    } # $data

    if ($open[-1]->local_name eq 'xl') {
      if ($open[-1]->has_attribute ('bare')) {
        pop @open;
      } else {
        if (($open[-1]->has_attribute_ns (undef, 'href') or
             ($open[-1]->children->length and
              $open[-1]->children->[0]->local_name eq 'href'))) {
          #
        } else {
          if ($open[-1]->children->length) {
            my $el = $doc->create_element_ns (MWNS, 'mw:href');
            $el->append_child ($_) for ($open[-1]->child_nodes->to_list);
            $open[-1]->append_child ($el);
          } else {
            $open[-1]->set_attribute (href => $open[-1]->text_content);
            $open[-1]->text_content ('');
          }
        }
      }
    } elsif ($open[-1]->local_name eq 'l' and
             $open[-1]->has_attribute_ns (undef, 'implied')) {
      pop @open;
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
    } elsif ($open[-1]->local_name eq 'gallery') {
      $line =~ s/^\s*//;
      if ($line =~ s{^</gallery\s*>}{}) {
        pop @open;
        $parse_inline->($line);
      } else {
        $line = 'File:'.$line
            if length $line and not $line =~ /^(?:File|Image):/;
        my $el = $doc->create_element_ns (MWNS, 'mw:l');
        $el->set_attribute (embed => '');
        $el->set_attribute (implied => '');
        $open[-1]->append_child ($el);
        push @open, $el;
        $parse_inline->($line);
      }
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
      if ($text =~ s/^([^:]*)://) {
        $parse_inline->($1);
        pop @open;
        my $el = $doc->create_element ('dd');
        $el->set_user_data (level => $level);
        $open[-1]->append_child ($el);
        push @open, $el;
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
    } elsif ($line =~ /^ .*$/s and
             not {ul => 1, ol => 1, dl => 1}->{$open[-1]->local_name}) {
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
