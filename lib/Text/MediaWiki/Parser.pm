package Text::MediaWiki::Parser;
use strict;
use warnings;

sub MWNS () { 'http://suikawiki.org/n/mw' }

my $HTMLPhrasing = {
  s => 1, strike => 1, ins => 1, u => 1, del => 1, code => 1, tt => 1,
  span => 1, font => 1, sub => 1, sup => 1, small => 1,
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
  li => 1, dt => 1, dd => 1, td => 1, th => 1,
  ref => 1, gallery => 1, nowiki => 1, references => 1, source => 1,
  include => 1, iparam => 1, placeholder => 1,
  l => 1, wref => 1, xl => 1, href => 1, comment => 1,
  ul => 1, ol => 1, dl => 1, caption => 1,
  includeonly => 1, noinclude => 1,
};

sub new ($) {
  return bless {}, $_[0];
} # new

sub parse_char_string ($$$) {
  my ($self, $data => $doc) = @_;

  $doc->manakai_is_html (0);
  $doc->strict_error_checking (0);
  $doc->inner_html ('<html xmlns="http://www.w3.org/1999/xhtml" xmlns:mw="'.MWNS.'"><head></head><body></body></html>');

  my @open = ($doc->body);
  $doc->body->set_user_data (level => 1);
  my $nowiki;
  my $current_tag;
  my $in_table = 0;

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

      if ($data =~ s/^\[\[//) {
        if ($data =~ s/^Category:([^|\]]+)(?:\|([^\]]+)|)\]\]//) {
          my $el = $doc->create_element_ns (MWNS, 'mw:category');
          $el->set_attribute (name => $1);
          $el->set_attribute (sortkey => $2) if defined $2;
          $open[-1]->append_child ($el);
        } else {
          $insert_p->();
          my $el = $doc->create_element_ns (MWNS, 'mw:l');
          $el->set_attribute ('embed' => '')
              if $data =~ /^(?:File:|Image:|[^:|\[\]]+:[^|\[\]]+\.(?i:jpe?g|gif|png|svg)(?=[|\]]))/;
          $open[-1]->append_child ($el);
          push @open, $el;
        }
      } elsif ($data =~ s/^#REDIRECT\s*\[\[//) {
        $insert_p->();
        my $el = $doc->create_element_ns (MWNS, 'mw:l');
        $el->set_attribute (redirect => '');
        $open[-1]->append_child ($el);
        push @open, $el;
      } elsif ($data =~ s/^\]//) {
        if ($open[-1]->local_name eq 'l' and $data =~ s/^\]//) { # ]]
          if ($data =~ s/^([A-Za-z]+)//) {
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
      } elsif ($data =~ s{^(https?://[A-Za-z0-9_:;.,()/?%#\$&+*~=-]+)}{}) {
        if ($open[-1]->local_name eq 'xl') {
          $open[-1]->manakai_append_text ($1);
        } else {
          $insert_p->();
          my $el = $doc->create_element_ns (MWNS, 'mw:xl');
          $el->set_attribute (bare => '');
          $el->manakai_append_text ($1);
          $open[-1]->append_child ($el);
        }
      } elsif ($data =~ s/^<($HTMLPhrasingPattern)\b((?>[^>"']|"[^"]*"|'[^']*')*)>//o) {
        $insert_p->();
        my $el = $doc->create_element ($1);
        $set_attrs->($2 => $el);
        $open[-1]->append_child ($el);
        push @open, $el;
      } elsif ($data =~ s/^<($HTMLFlowPattern)\b((?>[^>"']|"[^"]*"|'[^']*')*)>//o) {
        pop @open while not {body => 1, section => 1, includeonly => 1, noinclude => 1, table => 1, caption => 1, td => 1, th => 1, li => 1, dt => 1, dd => 1, %$HTMLFlow, p => 0}->{$open[-1]->local_name};
        my $el = $doc->create_element ($1);
        $set_attrs->($2 => $el);
        $open[-1]->append_child ($el);
        push @open, $el;
      } elsif ($data =~ s{^(</($HTMLPhrasingPattern|ref)\s*>)}{}o) {
        if ($open[-1]->local_name eq $2) {
          pop @open;
        } else {
          $insert_p->();
          $open[-1]->manakai_append_text ($1);
        }
      } elsif ($data =~ s{^(</($HTMLFlowPattern|references|source)\s*>)}{}o) {
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
      } elsif ($data =~ s/^<(gallery|references|source)\b((?>[^>"']|"[^"]*"|'[^']*')*)>//o) {
        pop @open while not {body => 1, section => 1, includeonly => 1, noinclude => 1, table => 1, caption => 1, td => 1, th => 1, li => 1, dt => 1, dd => 1, %$HTMLFlow, p => 0}->{$open[-1]->local_name};
        my $el = $doc->create_element_ns (MWNS, 'mw:'.$1);
        my $attrs = $2;
        my $close = $attrs =~ s{/\z}{};
        $set_attrs->($attrs => $el);
        $open[-1]->append_child ($el);
        unless ($close) {
          push @open, $el;
          if ($1 eq 'gallery') {
            $data =~ s/^\s+//;
            if (length $data) {
              my $el = $doc->create_element_ns (MWNS, 'mw:l');
              $el->set_attribute (embed => '');
              $el->set_attribute (implied => '');
              $open[-1]->append_child ($el);
              push @open, $el;
            }
          }
        }
      } elsif ($data =~ s/^<(ref)\b((?>[^>"']|"[^"]*"|'[^']*')*)>//) {
        $insert_p->();
        my $el = $doc->create_element_ns (MWNS, 'mw:'.$1);
        my $attrs = $2;
        my $close = $attrs =~ s{/\z}{};
        $set_attrs->($attrs => $el);
        $open[-1]->append_child ($el);
        push @open, $el unless $close;
      } elsif ($data =~ s{^<nowiki>}{}) {
        $insert_p->();
        my $el = $doc->create_element_ns (MWNS, 'mw:nowiki');
        $open[-1]->append_child ($el);
        push @open, $el;
        $nowiki = qr{</nowiki\s*>};
      } elsif ($data =~ s{^<pre\b((?>[^>"']|"[^"]*"|'[^']*')*)>}{}) {
        pop @open while not {body => 1, section => 1, includeonly => 1, noinclude => 1, table => 1, caption => 1, td => 1, th => 1, li => 1, dt => 1, dd => 1, %$HTMLFlow, p => 0}->{$open[-1]->local_name};
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
      } elsif ($data =~ s{^<(nowiki)\s*/>}{}) {
        my $el = $doc->create_element_ns (MWNS, 'mw:'.$1);
        $open[-1]->append_child ($el);
      } elsif ($data =~ s{^<(includeonly|noinclude)>}{}) {
        my $el = $doc->create_element_ns (MWNS, 'mw:'.$1);
        $el->set_user_data (level => 1);
        $open[-1]->append_child ($el);
        push @open, $el;
      } elsif ($data =~ s{^</(includeonly|noinclude)>}{}) {
        pop @open while not {body => 1, includeonly => 1, noinclude => 1, table => 1, caption => 1, td => 1, th => 1, li => 1, dt => 1, dd => 1, %$HTMLFlow, p => 0}->{$open[-1]->local_name};
        if ($open[-1]->local_name eq $1) {
          pop @open;
        } else {
          $open[-1]->manakai_append_text ("</$1>");
        }
      } elsif ($data =~ s{^(<[a-z0-9]+\b(?>[^>"']|"[^"]*"|'[^']*')*)$}{}) {
        $current_tag = $1;
      } elsif ($data =~ s{^<!--}{}) {
        my $el = $doc->create_element_ns (MWNS, 'mw:comment');
        $open[-1]->append_child ($el);
        push @open, $el;
        $nowiki = qr{-->};
      } elsif ($data =~ s/^\{\{//) {
        if ($data =~ s/^([A-Z]+|(?!(?:subst|safesubst|msgnw):)[a-z]+|#[a-z]+):\s*//) {
          my $el = $doc->create_element_ns (MWNS, 'mw:include');
          $el->set_attribute (wref => $1);
          $open[-1]->append_child ($el);
          push @open, $el;
        } elsif ($data =~ s/^([^{}|]+)//) {
          my $el = $doc->create_element_ns (MWNS, 'mw:include');
          my $wref = $1;
          if ($wref =~ s/^(?:(subst|safesubst|msgnw):)//) {
            $el->set_attribute (command => $1);
          }
          $wref =~ s/\s+\z//;
          $el->set_attribute (wref => $wref);
          $open[-1]->append_child ($el);
          push @open, $el;
        } elsif ($data =~ s/^\{([^{}|]+)//) {
          my $el = $doc->create_element_ns (MWNS, 'mw:placeholder');
          $el->set_attribute (name => $1);
          $open[-1]->append_child ($el);
          push @open, $el;
          if ($data =~ s/^\|//) {
            #
          } elsif ($data =~ s/^\}\}\}//) {
            pop @open;
          } else {
            pop @open;
          }
        } else {
          $insert_p->();
          $open[-1]->manakai_append_text ('{{');
        }
      } elsif ($data =~ s/^\}\}//) {
        if ($open[-1]->local_name eq 'include') {
          pop @open;
        } elsif ($open[-1]->local_name eq 'iparam') {
          pop @open;
          pop @open if $open[-1]->local_name eq 'include';
        } elsif ($data =~ s/^\}//) {
          if ($open[-1]->local_name eq 'placeholder') {
            pop @open;
          } else {
            $insert_p->();
            $open[-1]->manakai_append_text ('}}}');
          }
        } else {
          $insert_p->();
          $open[-1]->manakai_append_text ('}}');
        }
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
      } elsif ($data =~ s/^(&#?[a-z0-9]+;)//) {
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
            } elsif ($data =~ s/^(upright)(?:=([^\|\[\]]+)|)(?=\||\]\]|\z)//) {
              $open[-1]->set_attribute ($1 => defined $2 ? $2 : '');
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
            } elsif ($data =~ s/^(?=\||\]\]|\z)//) {
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
        } elsif ({td => 1, th => 1}->{$open[-1]->local_name} and
                 $data =~ s/^\|\s*//) {
          pop @open;
          my $el = $doc->create_element ('td');
          if ($data =~ s/^((?>[^|"'<|{\[]|"[^"]*"|'[^']*')*)\|(?!\|)\s*//) {
              $set_attrs->($1 => $el);
          }
          $el->set_user_data (level => 1);
          $open[-1]->append_child ($el);
          push @open, $el;
        } elsif ({include => 1, iparam => 1}->{$open[-1]->local_name}) {
          pop @open if $open[-1]->local_name eq 'iparam';
          $data =~ s/^\s+//;
          my $el = $doc->create_element_ns (MWNS, 'mw:iparam');
          if ($data =~ s/^([^<\{\}\[\]|!\s=]+)\s*=\s*//) {
            $el->set_attribute (name => $1);
          }
          $open[-1]->append_child ($el);
          push @open, $el;
        } else {
          $insert_p->();
          $open[-1]->manakai_append_text ('|');
        }
      } elsif ($data =~ s/^!!//) {
        if ({td => 1, th => 1}->{$open[-1]->local_name}) {
          $data =~ s/^\s+//;
          pop @open;
          my $el = $doc->create_element ('th');
          if ($data =~ s/^((?>[^|"'<{\[]|"[^"]*"|'[^']*')*)\|(?!\|)\s*//) {
              $set_attrs->($1 => $el);
          }
          $el->set_user_data (level => 1);
          $open[-1]->append_child ($el);
          push @open, $el;
        } else {
          $insert_p->();
          $open[-1]->manakai_append_text ('!!');
        }
      } elsif ($data =~ s/^__([A-Z]+)__//) {
        my $el = $doc->create_element_ns (MWNS, 'mw:behavior');
        $el->set_attribute (name => $1);
        $open[-1]->append_child ($el);
      } elsif ($data =~ s/^(\s)//) {
        if ($open[-1]->local_name eq 'xl') {
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
            $data =~ s/^\s+//;
            next;
          }
        }
        $insert_p->() unless $1 eq "\x0A";
        $open[-1]->manakai_append_text ($1)
            if $1 ne "\x0A" or
               $CanContainPhrasing->{$open[-1]->local_name};
      } elsif ($data =~ s/^([^&'<\{\}\[\]|!_#\s]+)// or $data =~ s/^(.)//s) {
        $insert_p->() unless $1 eq "\x0A";
        $open[-1]->manakai_append_text ($1)
            if $1 ne "\x0A" or
               $CanContainPhrasing->{$open[-1]->local_name};
      }
    } # $data

    if ($open[-1]->local_name eq 'xl') {
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
            if length $line and not $line =~ /^(?:File:|Image:|[^:]+:[^|\[\]]+\.(?i:jpe?g|gif|png)(?=[|\]]))/;
        my $el = $doc->create_element_ns (MWNS, 'mw:l');
        $el->set_attribute (embed => '');
        $el->set_attribute (implied => '');
        $open[-1]->append_child ($el);
        push @open, $el;
        $parse_inline->($line);
      }
    } elsif ($open[-1]->local_name eq 'iparam' and
             not $open[-1]->has_attribute_ns (undef, 'name') and
             $line =~ s/^\s*([^<\{\}\[\]|!\s=]+)\s*=\s*//) {
      $open[-1]->set_attribute (name => $1);
      $parse_inline->($line);
    } elsif ($line =~ /^(={1,6})\s*(.+?)\s*\1$/s) {
      my $level = length $1;
      my $text = $2;
      pop @open while not ({body => 1, section => 1, includeonly => 1, noinclude => 1, table => 1, caption => 1,
                            td => 1, th => 1}->{$open[-1]->local_name} and
                           ($open[-1]->get_user_data ('level') < $level or
                            $open[-1]->get_user_data ('level') == 1));
      my $next_level = $open[-1]->get_user_data ('level');
      $next_level++;
      while ($next_level < $level) {
        my $el = $doc->create_element ('section');
        $el->set_user_data (level => $next_level);
        $open[-1]->append_child ($el);
        push @open, $el;
        $next_level++;
      }

      my $el = $doc->create_element ('h1');
      $el->manakai_append_text ($text);
      if ($level == 1) {
        $open[-1]->append_child ($el);
      } else {
        my $el0 = $doc->create_element ('section');
        $el0->set_user_data (level => $level);
        $el0->append_child ($el);
        $open[-1]->append_child ($el0);
        push @open, $el0;
      }
    } elsif ($line =~ /^([*#:;]+)\s*(.+)$/s) {
      my $level = length $1;
      my $text = $2;
      my $list_type = {'*' => 'ul', '#' => 'ol',
                       ':' => 'dl', ';' => 'dl'}->{substr $1, -1};
      my $item_type = {'*' => 'li', '#' => 'li',
                       ':' => 'dd', ';' => 'dt'}->{substr $1, -1};

      pop @open while not (({li => 1, dt => 1, dd => 1}->{$open[-1]->local_name} and
                            $open[-1]->get_user_data ('level') <= $level) or
                           {body => 1, section => 1, includeonly => 1, noinclude => 1, table => 1, caption => 1,
                            td => 1, th => 1}->{$open[-1]->local_name});
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
      if ({dt => 1, dd => 1}->{$open[-1]->local_name} and
          $text =~ s/^([^:]*)://) {
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
      pop @open while not {body => 1, section => 1, includeonly => 1, noinclude => 1, table => 1, caption => 1,
                           td => 1, th => 1}->{$open[-1]->local_name};
      my $el = $doc->create_element_ns (MWNS, 'mw:nowiki');
      $el->set_attribute (pre => '');
      $open[-1]->append_child ($el);
      push @open, $el;
      $nowiki = qr{</nowiki\s*>};
      $parse_inline->($text);
    } elsif ($line =~ /^ .*$/s and
             not {ul => 1, ol => 1, dl => 1,
                  include => 1, iparam => 1}->{$open[-1]->local_name}) {
      pop @open while not {body => 1, section => 1, includeonly => 1, noinclude => 1, table => 1, caption => 1,
                           td => 1, th => 1,
                           pre => 1}->{$open[-1]->local_name};
      unless ($open[-1]->local_name eq 'pre') {
        my $el = $doc->create_element ('pre');
        $open[-1]->append_child ($el);
        push @open, $el;
        $parse_inline->(substr $line, 1);
      } else {
        $parse_inline->("\x0A" . substr $line, 1);
      }
    } elsif ($line =~ s/^\s*\{\|\s*//) {
      my $el = $doc->create_element ('table');
      if ($line =~ s/^((?>[^|"'<{\[]|"[^"]*"|'[^']*')*)//) {
        $set_attrs->($1 => $el);
      }
      $open[-1]->append_child ($el);
      push @open, $el;
      $in_table++;
      $parse_inline->($line);
    } elsif ($line =~ s/^\s*\|\}\s*//) {
      if ($in_table) {
        pop @open while not ($open[-1]->local_name eq 'table');
        pop @open; # table
        $in_table--;
        $parse_inline->($line);
      } else {
        $parse_inline->($line);
      }
    } elsif ($in_table and $line =~ s/^\s*\|-\s*//) {
      pop @open while not {table => 1, thead => 1, tbody => 1, tfoot => 1}->{$open[-1]->local_name};
      if ($open[-1]->local_name eq 'table') {
        my $el = $doc->create_element ('tbody');
        $open[-1]->append_child ($el);
        push @open, $el;
      }
      my $el = $doc->create_element ('tr');
      $set_attrs->($line => $el);
      $open[-1]->append_child ($el);
      push @open, $el;
    } elsif ($in_table and $line =~ s/^\s*\|\+\s*//) {
      pop @open while not $open[-1]->local_name eq 'table';
      my $el = $doc->create_element ('caption');
      if ($line =~ s/^((?>[^|"'<{\[]|"[^"]*"|'[^']*')*)\|(?!\|)\s*//) {
        $set_attrs->($1 => $el);
      }
      $open[-1]->append_child ($el);
      push @open, $el;
      $parse_inline->($line);
    } elsif ($in_table and $line =~ s/^\s*([|!])\s*//) {
      my $type = $1 eq '!' ? 'th' : 'td';
      pop @open while not {table => 1, thead => 1, tbody => 1, tfoot => 1,
                           tr => 1, td => 1, th => 1}->{$open[-1]->local_name};
      if ($open[-1]->local_name eq 'td' or
          $open[-1]->local_name eq 'th') {
        pop @open; # td/th
      }
      if ($open[-1]->local_name eq 'table') {
        my $el = $doc->create_element ('tbody');
        $open[-1]->append_child ($el);
        push @open, $el; # tbody
      }
      if (not $open[-1]->local_name eq 'tr') {
        my $el = $doc->create_element ('tr');
        $open[-1]->append_child ($el);
        push @open, $el; # tr
      }
      my $el = $doc->create_element ($type);
      if ($line =~ s/^((?>[^|"'<{\[]|"[^"]*"|'[^']*')*)\|(?!\|)\s*//) {
        $set_attrs->($1 => $el);
      }
      $el->set_user_data (level => 1);
      $open[-1]->append_child ($el);
      push @open, $el;
      $parse_inline->($line);
    } elsif ($line =~ /^----$/) {
      pop @open while not {body => 1, section => 1, includeonly => 1, noinclude => 1, table => 1, caption => 1,
                           td => 1, th => 1}->{$open[-1]->local_name};
      $open[-1]->append_child ($doc->create_element ('hr'));
    } elsif ($line =~ /^$/) {
      pop @open while not {body => 1, section => 1, includeonly => 1, noinclude => 1, table => 1, caption => 1,
                           td => 1, th => 1}->{$open[-1]->local_name};
      if ($open[-1]->local_name eq 'td' or
          $open[-1]->local_name eq 'th') {
        my $el = $doc->create_element ('p');
        $open[-1]->append_child ($el);
        push @open, $el;
      }
    } else {
      if ({li => 1, dt => 1, dd => 1, pre => 1}->{$open[-1]->local_name}) {
        pop @open while not {body => 1, section => 1, includeonly => 1, noinclude => 1, table => 1,
                             td => 1, th => 1}->{$open[-1]->local_name};
      }
      $parse_inline->("\x0A" . $line);
    }
  }

  $doc->strict_error_checking (1);
} # parse_char_string

1;
