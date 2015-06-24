package MWX::Extractor;
use strict;
use warnings;
use Promise;

sub process ($$) {
  my $doc = $_[1];
  my $data = {};

  use utf8;
  my $Defs = {
    data_includes => {
      駅情報 => 1,
    },
  };

  for my $include ($doc->query_selector_all ('include')->to_list) {
    my $wref = $include->get_attribute ('wref') // '';
    if ($Defs->{data_includes}->{$wref}) {
      my $d = {};
      for my $ip ($include->children->to_list) {
        next unless $ip->local_name eq 'iparam';
        my $name = $ip->get_attribute ('name') // '';
        my @value = $ip->child_nodes->to_list;
        if (@value and $value[0]->node_type == 3 and
            not $value[0]->text_content =~ /\S/) {
          shift @value;
        }
        if (@value and $value[-1]->node_type == 3 and
            not $value[-1]->text_content =~ /\S/) {
          pop @value;
        }
        if (@value == 1) {
          if ($value[0]->node_type == 1) {
            if ($value[0]->local_name eq 'l' and
                (not @{$value[0]->attributes} or
                 (@{$value[0]->attributes} == 1 and
                  $value[0]->has_attribute ('wref')))) {
              $d->{$name} = ['l',
                             $value[0]->text_content,
                             $value[0]->get_attribute ('wref') // $value[0]->text_content];
            } else {
              $d->{$name} = ['unparsed', $value[0]->outer_html];
            }
          } elsif ($value[0]->node_type == 3) {
            $d->{$name} = ['string', $value[0]->text_content];
          }
        } elsif (@value) {
          $d->{$name} = ['unparsed', $ip->inner_html];
        }
      }
      push @{$data->{includes}->{$wref} ||= []}, $d;
    }
  }

  return Promise->resolve ($data);
} # process

1;
