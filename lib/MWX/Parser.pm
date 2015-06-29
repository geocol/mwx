package MWX::Parser;
use strict;
use warnings;

sub new ($) {
  return bless {}, $_[0];
} # new

sub parse_char_string ($$) {
  my ($self, $s) = @_;

  my $defs = {};
  my $current = {};
  my $current_l1 = {};
  my $current_list = [];

  for my $line (split /\x0D?\x0A/, $s) {
    if ($line =~ /^\@(\@?)(\w+)\s+(\S.+?)\s*$/) {
      my $cont = $1;
      my $type = $2;
      my $name = $3;
      if ($cont) {
        $current = $defs->{$type}->{$name} = $current_l1;
      } else {
        $current_l1 = $current = $defs->{$type}->{$name} = {};
      }
      $current_list = [];
    } elsif ($line =~ /^\$(\$?)(\w+)\s+(\S.+?)\s*$/) {
      my $cont = $1;
      my $type = $2;
      my $name = $3;
      if ($cont) {
        $current_l1->{fields}->{$type}->{$name} = $current;
      } else {
        $current = $current_l1->{fields}->{$type}->{$name} = {};
      }
      $current_list = [];
    } elsif ($line =~ /^=(\w+)\s*$/) {
      $current->{flags}->{$1} = 1;
      $current_list = [];
    } elsif ($line =~ /^(\w+)=(.*?)\s*$/) {
      $current->{props}->{$1} = $2;
      $current_list = [];
    } elsif ($line =~ /^(\w+)\+\s*$/) {
      $current_list = $current->{lists}->{$1} = [];
    } elsif ($line =~ s/^  (?=\S)//) {
      push @$current_list, $line;
    } elsif ($line =~ /\S/) {
      warn "Bad line: |$line|";
    }
  }

  return $defs;
} # parse_char_string

1;
