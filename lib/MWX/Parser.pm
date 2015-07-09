package MWX::Parser;
use strict;
use warnings;

sub new ($) {
  return bless {}, $_[0];
} # new

sub parse_char_string ($$) {
  my ($self, $s) = @_;

  my $defs = {};
  my $currents = [];
  my $current_l1s = [];
  my $current_lists = [];

  for my $line (split /\x0D?\x0A/, $s) {
    if ($line =~ /^\@(\@?)(\w+)\s+(\S.+?)\s*$/) {
      my $cont = $1;
      my $type = $2;
      my $name = $3;
      if ($cont) {
        push @$currents, $defs->{$type}->{$name} ||= {};
      } else {
        $currents = $current_l1s = [$defs->{$type}->{$name} ||= {}];
      }
      $current_lists = [];
    } elsif ($line =~ /^\$(\$?)(\w+)\s+(\S.+?)\s*$/) {
      my $cont = $1;
      my $type = $2;
      my $name = $3;
      if ($cont) {
        push @$currents, $_->{fields}->{$type}->{$name} ||= {}
            for @$current_l1s;
      } else {
        $currents = [map { $_->{fields}->{$type}->{$name} ||= {} } @$current_l1s];
      }
      $current_lists = [];
    } elsif ($line =~ /^=(\w+)\s*$/) {
      $_->{flags}->{$1} = 1 for @$currents;
      $current_lists = [];
    } elsif ($line =~ /^(\w+)=(.*?)\s*$/) {
      $_->{props}->{$1} = $2 for @$currents;
      $current_lists = [];
    } elsif ($line =~ /^(\w+)\+\s*$/) {
      $current_lists = [];
      push @$current_lists, $_->{lists}->{$1} = [] for @$currents;
    } elsif ($line =~ s/^  (?=\S)//) {
      push @$_, $line for @$current_lists;
    } elsif ($line =~ /\S/) {
      warn "Bad line: |$line|";
    }
  }

  return $defs;
} # parse_char_string

1;
