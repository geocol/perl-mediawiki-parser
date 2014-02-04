package MWDOM::Extractor;
use strict;
use warnings;
use MWDOM::WRef;
use Char::Normalize::FullwidthHalfwidth qw(get_fwhw_normalized);

sub MWNS () { q<http://suikawiki.org/n/mw> }
sub HTMLNS () { q<http://www.w3.org/1999/xhtml> }

sub new_from_document ($$) {
  return bless {doc => $_[1]}, $_[0];
} # new_from_document

sub redirect_wref ($) {
  my $self = $_[0];
  return $self->{redirect_wref} if exists $self->{redirect_wref};
  my $de = $self->{doc}->document_element;
  return $self->{redirect_wref}
      = defined $de ? MWDOM::WRef->new_from_string_or_undef ($de->get_attribute_ns (MWNS, 'redirect')) : undef;
} # redirect_wref

sub abstract_text ($) {
  my $self = $_[0];
  return $self->{abstract_text} if exists $self->{abstract_text};
  my $p = $self->{doc}->query_selector ('body > p, section > p');
  unless (defined $p) {
    return $self->{abstract_text} = undef;
  }

  my $result = [];
  for (@{$p->child_nodes}) {
    if ($_->node_type == $_->ELEMENT_NODE) {
      my $ns = $_->namespace_uri || '';
      if ($ns eq MWNS) {
        my $ln = $_->local_name;
        if ($ln eq 'l') {
          unless ($_->has_attribute_ns (undef, 'embed')) {
            push @$result, $_->text_content;
          }
        } elsif ($ln eq 'ref') {
          #
        } elsif ($ln eq 'comment') {
          #
        } else {
          push @$result, $_->text_content;
        }
      } else {
        push @$result, $_->text_content;
      }
    } elsif ($_->node_type == $_->TEXT_NODE) {
      push @$result, $_->data;
    }
  }
  $self->{abstract_text} = get_fwhw_normalized join '', @$result;
  $self->{abstract_text} =~ s/\A\s+//;
  $self->{abstract_text} =~ s/\s+\z//;
  $self->{abstract_text} =~ s/\s+/ /;
  return $self->{abstract_text};
} # abstract_text

sub dict_defs ($) {
  my $self = $_[0];

  my $lis = $self->{doc}->query_selector_all ('ol > li');
  my @result;
  for my $li (@$lis) {
    my $text = [];
    for my $node (@{$li->child_nodes}) {
      if ($node->node_type == $node->ELEMENT_NODE) {
        if (($node->namespace_uri || '') eq MWNS) {
          my $ln = $node->local_name;
          if ($ln eq 'ref' or $ln eq 'comment') {
            #
          } elsif ($ln eq 'include') {
            #
          } else {
            push @$text, $node->text_content;
          }
        } elsif (($node->namespace_uri || '') eq HTMLNS) {
          my $ln = $node->local_name;
          if ($ln eq 'ul' or $ln eq 'dl' or $ln eq 'ol') {
            #
          } else {
            push @$text, $node->text_content;
          }
        } else {
          push @$text, $node->text_content;
        }
      } elsif ($node->node_type == $node->TEXT_NODE) {
        push @$text, $node->data;
      }
    }
    $text = get_fwhw_normalized join '', @$text;
    $text =~ s/\A\s+//;
    $text =~ s/\s+\z//;
    $text =~ s/\s+/ /;
    push @result, $text if length $text;
  }

  return \@result;
} # dict_defs

1;
