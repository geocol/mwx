package MWX::Extractor;
use utf8;
use strict;
use warnings;
use Promise;

sub _tc ($) {
  return $_[0]->text_content;
} # _tc

sub parse_include ($);
sub parse_include ($) {
  my $include = $_[0];
  my $wref = $include->get_attribute ('wref') // '';

  my $Defs = {
    data_includes => {
      駅情報 => 1,
      ウィキ座標2段度分秒 => 1,
      駅番号c => 1,
      駅番号s => 1,
    },
  };

  return undef unless $Defs->{data_includes}->{$wref};

  my $d = {};
  my $i = 0;
  for my $ip ($include->children->to_list) {
    next unless $ip->local_name eq 'iparam';
    my $name = $ip->get_attribute ('name') // $i;
    $i++;
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
        my $ln = $value[0]->local_name;
        if ($ln eq 'l' and not $value[0]->has_attribute ('embed')) {
          $d->{$name} = ['l',
                         $value[0]->text_content,
                         $value[0]->get_attribute ('wref') // $value[0]->text_content];
        } elsif ($ln eq 'include') {
          my $x = parse_include $value[0];
          if (defined $x) {
            $d->{$name} = [$value[0]->get_attribute ('wref'), $x];
          } else {
            $d->{$name} = ['unparsed', $value[0]->outer_html];
          }
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
  return $d;
} # parse_include

sub process ($$) {
  my $doc = $_[1];
  my $data = {};

  for my $section ($doc->query_selector_all ('section')->to_list) {
    my $h1 = $section->first_element_child;
    next unless defined $h1 and $h1->local_name eq 'h1';
    my $title = $h1->text_content;

    if ($title eq '駅周辺') {
      my $d = {items => []};
      for my $ul ($section->children->to_list) {
        next unless $ul->local_name eq 'ul';
        for my $li ($ul->children->to_list) {
          next unless $li->local_name eq 'li';
          my @t = $li->child_nodes->to_list;
          if (@t and not grep {
            not (
              $_->node_type == 3 or
              ($_->local_name eq 'l' and not $_->has_attribute ('embed'))
            )
          } @t) {
            push @{$d->{items}}, ['string', _tc $li];
          } else {
            push @{$d->{items}}, ['unparsed', $li->inner_html];
          }
        }
      }
      push @{$data->{lists}->{$title} ||= []}, $d if @{$d->{items}};
    }
  }

  for my $include ($doc->query_selector_all ('include')->to_list) {
    my $d = parse_include $include;
    push @{$data->{includes}->{$include->get_attribute ('wref')} ||= []}, $d
        if defined $d;
  }

  return Promise->resolve ($data);
} # process

1;
