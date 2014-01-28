package MWDOM::WRef;
use strict;
use warnings;

sub new_from_string ($$) {
  my ($name, $section) = split /#/, $_[1], 2;
  return bless {name => $name, section => $section}, $_[0];
} # new_from_string

sub new_from_string_or_undef ($$) {
  return defined $_[1] ? $_[0]->new_from_string ($_[1]) : undef;
} # new_from_string_or_undef

sub name ($) {
  return $_[0]->{name};
} # name

sub section ($) {
  return $_[0]->{section};
} # section

1;
