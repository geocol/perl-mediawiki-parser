package MWDOM::Extractor;
use strict;
use warnings;
use MWDOM::WRef;

sub MWNS () { q<http://suikawiki.org/n/mw> }

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
  $self->{abstract_text} = join '', @$result;
  $self->{abstract_text} =~ s/\A\s+//;
  $self->{abstract_text} =~ s/\s+\z//;
  $self->{abstract_text} =~ s/\s+/ /;
  return $self->{abstract_text};
} # abstract_text

1;
