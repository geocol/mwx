package MWX::Extractor;
use utf8;
use strict;
use warnings;
use Promise;
use Char::Normalize::FullwidthHalfwidth qw(get_fwhw_normalized);

sub _tc ($) {
  return $_[0]->text_content;
} # _tc

sub _n ($) {
  my $s = $_[0];
  $s =~ s/\s+/ /;
  $s =~ s/^ //;
  $s =~ s/ $//;
  return get_fwhw_normalized $s;
} # _n

sub _expand_l ($) {
  return ['l',
          $_[0]->text_content,
          $_[0]->get_attribute ('wref') // $_[0]->text_content];
} # _expand_l

sub parse_include ($);
sub parse_value ($$);

my $IncludeDefs = {};
$IncludeDefs->{$_}->{is_structure} = 1 for qw(
      駅情報
      ウィキ座標2段度分秒
      駅番号c
      駅番号s
);

for (
  ['駅情報', '所属路線', ['with-annotation']],
  ['駅情報', '所属事業者', ['with-annotation']],
  ['駅情報', '前の駅', ['next-station']],
  ['駅情報', '次の駅', ['next-station']],
  ['駅情報', '開業年月日', ['date']],
) {
  $IncludeDefs->{$_->[0]}->{params}->{$_->[1]}->{parsing_rules} = $_->[2];
}

my $SectionDefs = {};
$SectionDefs->{'駅周辺'}->{parsing_rule} = 'list';
$SectionDefs->{'駅周辺'}->{item_parsing_rules} = [
  'nested-list',
  'with-annotation',
  'ignore-links',
];

my $RuleDefs = {};
$RuleDefs->{'with-annotation'} = {
  code => sub {
    my $nodes = $_[1];
    if (@$nodes == 2 and
        $nodes->[0]->node_type == 1 and $nodes->[0]->local_name eq 'l' and not $nodes->[0]->has_attribute ('embed') and
        $nodes->[1]->node_type == 3) {
      my $v = _n $nodes->[1]->text_content;
      if ($v =~ /^\((.+)\)$/) {
        return ['with-annotation',
                _expand_l $nodes->[0],
                $1];
      }
    } elsif (@$nodes == 1 and $nodes->[0]->node_type == 3) {
      my $v = _n $nodes->[0]->text_content;
      if ($v =~ /^([^()]+) ?\(([^()]+)\)$/) {
        return ['with-annotation', $1, $2];
      }
    } elsif (@$nodes >= 2 and
             $nodes->[0]->local_name eq 'l' and not $nodes->[0]->has_attribute ('embed')) {
      my $v = _n join '', map { $_->text_content } @$nodes[1..$#$nodes];
      if ($v =~ /^\(([^()]+)\)$/) {
        $v = $1;
        unless (grep {
          not (
            $_->node_type == 3 or
            ($_->node_type == 1 and $_->local_name eq 'l' and not $_->has_attribute ('embed'))
          );
        } @$nodes) {
          return ['with-annotation', _expand_l $nodes->[0], $v];
        }
      }
    }
    return undef;
  },
}; # with-annotation
$RuleDefs->{'next-station'} = {
  code => sub {
    my $nodes = $_[1];
    if (@$nodes == 2 and
        $nodes->[0]->node_type == 1 and $nodes->[0]->local_name eq 'l' and not $nodes->[0]->has_attribute ('embed') and
        $nodes->[1]->node_type == 3) {
      my $v = $nodes->[1]->text_content;
      if ($v =~ /^\s+\S/) {
        return ['next-station',
                _expand_l $nodes->[0],
                _n $v];
      }
    } elsif (@$nodes == 2 and
             $nodes->[1]->node_type == 1 and $nodes->[1]->local_name eq 'l' and not $nodes->[1]->has_attribute ('embed') and
             $nodes->[0]->node_type == 3) {
      my $v = $nodes->[0]->text_content;
      if ($v =~ /\S\s+\z/) {
        return ['next-station',
                _expand_l $nodes->[1],
                _n $v];
      }
    }
    return undef;
  },
}; # next-station
$RuleDefs->{'date'} = {
  code => sub {
    my $nodes = $_[1];
    my $tc = _n join '', map { $_->text_content } @$nodes;
    if ($tc =~ /^([0-9]+)年([0-9]+)月([0-9]+)日$/) {
      return ['date', $1, $2, $3];
    } elsif ($tc =~ /^([0-9]+)年\s*\([^()]+\)\s*([0-9]+)月([0-9]+)日$/) {
      return ['date', $1, $2, $3];
    }
    return undef;
  },
}; # date
$RuleDefs->{'nested-list'} = {
  code => sub {
    my ($ctx_def, $nodes) = @_;
    if (@$nodes and $nodes->[-1]->node_type == 1 and $nodes->[-1]->local_name eq 'ul') {
      my $list = pop @$nodes;
      $list = ['list', map { parse_value $ctx_def, $_ } grep { $_->local_name eq 'li' } $list->children->to_list];
      if (@$nodes) {
        return ['with-list', (parse_value $ctx_def, $nodes), $list];
      } else {
        return $list;
      }
    }
    return undef;
  },
}; # nested-list
$RuleDefs->{'ignore-links'} = {
  code => sub {
    my ($ctx_def, $nodes) = @_;
    if (@$nodes and not grep {
      not (
        $_->node_type == 3 or
        ($_->local_name eq 'l' and not $_->has_attribute ('embed'))
      )
    } @$nodes) {
      return ['string', join '', map { $_->text_content } @$nodes];
    }
    return undef;
  },
}; # ignore-links

sub parse_value ($$) {
  my ($ctx_def, $parent) = @_;

  my @value;
  if (ref $parent eq 'ARRAY') {
    @value = @$parent;
  } else {
    my @item = (my $last = []);
    for ($parent->child_nodes->to_list) {
      if ($_->node_type == 1 and $_->local_name eq 'br') {
        push @item, $last = [];
      } else {
        push @$last, $_;
      }
    }
    @item = grep { !!@$_ } @item;
    if (@item == 1) {
      @value = @{$item[0]};
    } elsif (@item == 0) {
      return undef;
    } else {
      return ['list', grep { defined } map { parse_value $ctx_def, $_ } @item];
    }
  }

  if (@value and $value[0]->node_type == 3 and
      not $value[0]->text_content =~ /\S/) {
    shift @value;
  }
  my @comment;
  {
    if (@value and $value[-1]->node_type == 3 and
        not $value[-1]->text_content =~ /\S/) {
      pop @value;
      redo;
    }

    if (@value and $value[-1]->node_type == 1 and
        $value[-1]->local_name eq 'comment') {
      unshift @comment, pop @value;
      redo;
    }
  }
  if (@comment) {
    return ['with-comment', (parse_value $ctx_def, \@value), map { $_->text_content } @comment];
  }

  if (@value == 1) {
    if ($value[0]->node_type == 1) {
      my $ln = $value[0]->local_name;
      if ($ln eq 'l' and not $value[0]->has_attribute ('embed')) {
        return _expand_l $value[0];
      } elsif ($ln eq 'include') {
        my $x = parse_include $value[0];
        return ['='.$value[0]->get_attribute ('wref'), $x] if defined $x;
      }
      return ['unparsed', $value[0]->outer_html];
    } elsif ($value[0]->node_type == 3) {
      return ['string', $value[0]->text_content];
    }
  }

  for my $rule_name (@{$ctx_def->{parsing_rules} or []}) {
    my $rule_def = $RuleDefs->{$rule_name};
    unless ($rule_def->{code}) {
      warn "Rule |$rule_name| is not defined";
      next;
    }
    my $v = $rule_def->{code}->($ctx_def, \@value);
    if (defined $v) {
      return $v;
    }
  }

  if (@value) {
    if (ref $parent eq 'ARRAY') {
      return ['unparsed', map {
        $_->node_type == 1 ? $_->outer_html : ['string', $_->text_content];
      } @value];
    } else {
      return ['unparsed', $parent->inner_html];
    }
  } else {
    return undef;
  }
} # parse_value

sub parse_include ($) {
  my $include = $_[0];
  my $wref = $include->get_attribute ('wref') // '';
  my $inc_def = $IncludeDefs->{$wref};
  return undef unless $inc_def->{is_structure};

  my $d = {};
  my $i = 0;
  for my $ip ($include->children->to_list) {
    next unless $ip->local_name eq 'iparam';
    my $name = $ip->get_attribute ('name') // $i;
    $i++;
    my $v = parse_value $inc_def->{params}->{$name}, $ip;
    $d->{$name} = $v if defined $v;
  }
  return $d;
} # parse_include

sub process ($$) {
  my $doc = $_[1];
  my $data = {};

  for my $section ($doc->query_selector_all ('section')->to_list) {
    my $h1 = $section->first_element_child;
    next unless defined $h1 and $h1->local_name eq 'h1';
    my $title = _n $h1->text_content;
    my $sec_def = $SectionDefs->{$title};
    my $rule_name = $sec_def->{parsing_rule} or next;
    if ($rule_name eq 'list') {
      my $d = {items => []};
      for my $ul ($section->children->to_list) {
        next unless $ul->local_name eq 'ul';
        for my $li ($ul->children->to_list) {
          next unless $li->local_name eq 'li';

          my $v = parse_value {parsing_rules => $sec_def->{item_parsing_rules}}, $li;
          push @{$d->{items}}, $v if defined $v;
        }
      }
      push @{$data->{lists}->{$title} ||= []}, $d if @{$d->{items}};
    } else {
      warn "Section parsing rule |$rule_name| is not defined";
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
