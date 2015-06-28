package MWX::Extractor;
use utf8;
use strict;
use warnings;
use Promise;
use Char::Normalize::FullwidthHalfwidth qw(get_fwhw_normalized);

my $IncludeDefs = {};

sub _tc ($) {
  return $_[0]->text_content;
} # _tc

sub _ignore_links ($) {
  my $nodes = $_[0];
  my @l;
  my @t;
  if (@$nodes and not grep {
    not (
      $_->node_type == 3 or
      ($_->local_name eq 'l' and not $_->has_attribute ('embed')) or
      ($_->local_name eq 'include' and $_->get_attribute ('wref') eq '仮リンク') or
      ($_->local_name eq 'ref') or
      ($_->local_name eq 'comment') or
      ($_->local_name eq 'include' and $IncludeDefs->{$_->get_attribute ('wref') // ''}->{ignorable})
    )
  } @$nodes) {
    for (@$nodes) {
      if ($_->node_type == 1) {
        if ($_->local_name eq 'ref' or $_->local_name eq 'comment') {
          #
        } elsif ($_->local_name eq 'include') {
          if ($_->get_attribute ('wref') eq '仮リンク') {
            for ($_->children->to_list) {
              next unless $_->local_name eq 'iparam';
              push @t, $_->text_content;
              push @l, $_;
              last;
            }
          }
        } else { # l
          push @t, $_->text_content;
          push @l, $_;
        }
      } else {
        push @t, $_->text_content;
      }
    }
  } else {
    return (undef, undef);
  }
  return (\@t, \@l);
} # _ignore_links

sub _n ($) {
  my $s = $_[0];
  $s =~ s/\s+/ /g;
  $s =~ s/^ //;
  $s =~ s/ $//;
  return get_fwhw_normalized $s;
} # _n

sub _expand_l ($) {
  if ($_[0]->local_name eq 'include') { # wref=仮リンク
    for ($_[0]->children->to_list) {
      next unless $_->local_name eq 'iparam';
      my $t = $_->text_content;
      return ['l', $t, $t];
    }
    return undef;
  } else {
    return ['l',
            $_[0]->text_content,
            $_[0]->get_attribute ('wref') // $_[0]->text_content];
  }
} # _expand_l

sub parse_include ($);
sub parse_value ($$);

$IncludeDefs->{$_}->{is_structure} = 1 for qw(
      駅情報
      ウィキ座標2段度分秒 ウィキ座標度分秒
      駅番号c
      駅番号s
);

$IncludeDefs->{$_}->{ignorable} = 1 for qw(要検証 audio);

for (
  ['駅情報', '所属路線', ['with-annotation']],
  ['駅情報', '所属事業者', ['with-annotation']],
  ['駅情報', '前の駅', ['next-station']],
  ['駅情報', '次の駅', ['next-station']],
  ['駅情報', '開業年月日', ['date']],
  ['駅情報', '所在地', ['ignore-links']],
  ['駅情報', '所属路線', ['with-annotation', '路線']],
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

$SectionDefs->{$_}->{parsing_rule} = 'list',
$SectionDefs->{$_}->{item_parsing_rules} = [
  'ignore-links',
],
$SectionDefs->{$_}->{item_filters} = [
  'ignore-comment',
],
$SectionDefs->{$_}->{item_string_filters} = [
  'year-prefixed',
] for qw(できごと 日本の自治体改編 フィクションのできごと);

$SectionDefs->{$_}->{parsing_rule} = 'list',
$SectionDefs->{$_}->{item_parsing_rules} = [
  'nested-indent',
  'holiday',
  'ignore-links',
],
$SectionDefs->{$_}->{item_filters} = [
  'ignore-comment',
  'indent-as-desc',
],
$SectionDefs->{$_}->{item_string_filters} = [
] for qw(記念日・年中行事);

$SectionDefs->{$_}->{parsing_rule} = 'list',
$SectionDefs->{$_}->{item_parsing_rules} = [
  'year-prefixed-name',
],
$SectionDefs->{$_}->{item_filters} = [
  'ignore-comment',
],
$SectionDefs->{$_}->{item_string_filters} = [
] for qw(誕生日 忌日 誕生日(フィクション) );

my $RuleDefs = {};
$RuleDefs->{'with-annotation'} = {
  code => sub {
    my $nodes = $_[1];
    if (@$nodes == 2 and
        $nodes->[0]->node_type == 1 and
        (($nodes->[0]->local_name eq 'l' and not $nodes->[0]->has_attribute ('embed')) or
         ($nodes->[0]->local_name eq 'include' and $nodes->[0]->get_attribute ('wref') eq '仮リンク')) and
        $nodes->[1]->node_type == 3) {
      my $v = _n $nodes->[1]->text_content;
      if ($v =~ /^\((.+)\)$/) {
        return ['with-annotation',
                _expand_l $nodes->[0],
                $1];
      }
    } elsif (@$nodes >= 2 and
             $nodes->[0]->node_type == 1 and
             (($nodes->[0]->local_name eq 'l' and not $nodes->[0]->has_attribute ('embed')) or
              ($nodes->[0]->local_name eq 'include' and $nodes->[0]->get_attribute ('wref') eq '仮リンク'))) {
      my $v = _n join '', map { $_->text_content } @$nodes[1..$#$nodes];
      if ($v =~ /^\(([^()]+)\)$/) {
        $v = $1;
        unless (grep {
          not (
            $_->node_type == 3 or
            ($_->node_type == 1 and
             (($_->local_name eq 'l' and not $_->has_attribute ('embed')) or
              ($_->local_name eq 'include' and $_->get_attribute ('wref') eq '仮リンク')))
          );
        } @$nodes) {
          return ['with-annotation', _expand_l $nodes->[0], $v];
        }
      }
    } elsif (not grep { $_->node_type == 1 } @$nodes) {
      my $v = _n join '', map { $_->text_content } @$nodes;
      if ($v =~ /^([^()]+)\(([^()]+)\)$/) {
        return ['with-annotation', $1, $2];
      }
    }
    return undef;
  },
}; # with-annotation
$RuleDefs->{'next-station'} = {
  code => sub {
    my $nodes = $_[1];
    if (@$nodes == 2 and
        $nodes->[0]->node_type == 1 and
        (($nodes->[0]->local_name eq 'l' and not $nodes->[0]->has_attribute ('embed')) or
         ($nodes->[0]->local_name eq 'include' and $nodes->[0]->get_attribute ('wref') eq '仮リンク')) and
        $nodes->[1]->node_type == 3) {
      my $v = $nodes->[1]->text_content;
      if ($v =~ /^\s+\S/) {
        return ['next-station',
                _expand_l $nodes->[0],
                _n $v];
      }
    } elsif (@$nodes == 2 and
             $nodes->[1]->node_type == 1 and
             (($nodes->[1]->local_name eq 'l' and not $nodes->[1]->has_attribute ('embed')) or
              ($nodes->[1] eq 'include' and $nodes->[1]->get_attribute ('wref') eq '仮リンク')) and
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
$RuleDefs->{'nested-indent'} = {
  code => sub {
    my ($ctx_def, $nodes) = @_;
    if (@$nodes and
        $nodes->[-1]->node_type == 1 and $nodes->[-1]->local_name eq 'dl' and
        $nodes->[-1]->children->length == 1) { # dd
      my $list = pop @$nodes;
      $list = parse_value $ctx_def, $list->children->[0];
      if (@$nodes) {
        return ['with-indent', (parse_value $ctx_def, $nodes), $list];
      } else {
        return $list;
      }
    }
    return undef;
  },
}; # nested-indent
$RuleDefs->{'ignore-links'} = {
  code => sub {
    my ($ctx_def, $nodes) = @_;
    my ($ts, $ls) = _ignore_links $nodes;
    return undef if not defined $ts or not @$ls;
    return ['string', join '', @$ts];
  },
}; # ignore-links
$RuleDefs->{'路線'} = {
  code => sub {
    my ($ctx_def, $nodes) = @_;
    my @node;
    for (@$nodes) {
      if ($_->node_type == 1) {
        push @node, $_;
      } elsif ($_->node_type == 3) {
        return undef if $_->text_content =~ /\S/;
      }
    }
    if (@node == 2 and
        $node[0]->local_name eq 'span' and $node[0]->has_attribute ('style') and
        (($node[1]->local_name eq 'l' and not $node[1]->has_attribute ('embed')) or
         ($node[1]->local_name eq 'include' and $node[1]->get_attribute ('wref') eq '仮リンク'))) {
      if ($node[0]->get_attribute ('style') =~ /^\s*color:\s*(\S+)\s*$/) {
        return ['路線-colored', _expand_l $node[1], $1];
      }
    }
    return undef;
  },
}; # 路線
$RuleDefs->{'year-prefixed-name'} = {
  code => sub {
    my ($ctx_def, $nodes) = @_;
    my ($ts, $ls) = _ignore_links $nodes;
    return undef unless defined $ts;

    my $s = _n join '', @$ts;
    $s =~ s/ ?\([+*] [0-9]+年[?頃]?\)$//;
    my $v;
    if ($s =~ s/^([0-9]+)年 ?- (.+?)、//) {
      $v = {year => $1, name => $2, desc => $s};
    } elsif ($s =~ s/^([0-9]+)年 ?- (.+?)$//) {
      $v = {year => $1, name => $2};
    } elsif ($s =~ s{^([0-9]+)年\(([\w/]+年[0-9]+月[0-9]+日)\) ?- (.+?)、}{}) {
      $v = {year => $1, local_date => $2, name => $3, desc => $s};
    } elsif ($s =~ s{^([0-9]+)年\(([\w/]+年[0-9]+月[0-9]+日)\) ?- (.+?)$}{}) {
      $v = {year => $1, local_date => $2, name => $3};
    } elsif ($s =~ s/^生年不[明詳] ?- (.+?)、//) {
      $v = {name => $1, desc => $s};
    } elsif ($s =~ s/^生年不[明詳] ?- (.+?)$//) {
      $v = {name => $1};
    } else {
      return undef;
    }

    $v->{name} =~ s/ ?\(:en:[^()]+\)$//; # link to en.wikipedia
    if (@$ls >= 2 and $v->{name} eq _n $ls->[1]->text_content) {
      $v->{wref} = $ls->[1]->get_attribute ('wref') // $ls->[1]->text_content;
    } elsif (@$ls > 0 and $v->{name} eq _n $ls->[0]->text_content) {
      $v->{wref} = $ls->[0]->get_attribute ('wref') // $ls->[0]->text_content;
    }
    return $v;
  },
}; # year-prefixed-name
$RuleDefs->{'holiday'} = {
  code => sub {
    my ($ctx_def, $nodes) = @_;
    if (@$nodes > 2 and
        $nodes->[-1]->node_type == 3 and $nodes->[-1]->text_content =~ /^[)\）]$/ and
        $nodes->[-2]->node_type == 1 and $nodes->[-2]->local_name eq 'include' and $nodes->[-2]->get_attribute ('wref') =~ /^([A-Z]+)$/) {
      my $region = $1;
      pop @$nodes;
      pop @$nodes;

      my ($ts, $ls) = _ignore_links $nodes;
      return undef unless defined $ts;
      $ts->[-1] =~ s/ ?[(\（]$// if @$ts;
      my $s = _n join '', @$ts;
      my $v = {region => $region, name => $s};
      if (@$ls and $ls->[0]->text_content eq $v->{name}) {
        $v->{wref} = $ls->[0]->get_attribute ('wref') // $ls->[0]->text_content;
      }
      return $v;
    }
    return undef;
  },
}; # holiday

sub apply_filters ($$);

my $FilterDefs = {};
$FilterDefs->{'ignore-comment'} = sub {
  my ($def, $v) = @_;
  if (ref $v eq 'ARRAY' and $v->[0] eq 'with-comment') {
    $v = apply_filters $def, $v->[1]
  }
  return $v;
}; # ignore-comment
$FilterDefs->{'indent-as-desc'} = sub {
  my ($def, $v) = @_;
  if (ref $v eq 'ARRAY' and
      $v->[0] eq 'with-indent' and
      ref $v->[1] eq 'HASH') {
    $v->[2] = apply_filters $def, $v->[2];
    if (ref $v->[2] eq 'ARRAY' and $v->[2]->[0] eq 'string') {
      $v->[1]->{desc} = $v->[2]->[1];
      $v = $v->[1];
    }
  }
  return $v;
}; # indent-as-desc

my $StringFilterDefs = {};
$StringFilterDefs->{'year-prefixed'} = sub {
  my $s = _n $_[1];
  $s =~ s/ ?\(:en:[^()]+\)$//; # link to en.wikipedia
  if ($s =~ s/^([0-9]+)年 ?- //) {
    return {year => $1, desc => $s};
  } elsif ($s =~ s{^([0-9]+)年\(([\w/]+年[0-9]+月[0-9]+日)\) ?- }{}) {
    return {year => $1, local_date => $2, desc => $s};
  }
  return undef;
}; # year-prefixed

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

  if (@value == 1) {
    if ($value[0]->node_type == 1) {
      my $ln = $value[0]->local_name;
      if (($ln eq 'l' and not $value[0]->has_attribute ('embed')) or
          ($ln eq 'include' and $value[0]->get_attribute ('wref') eq '仮リンク')) {
        return _expand_l $value[0];
      } elsif ($ln eq 'include') {
        my $x = parse_include $value[0];
        return ['='.$value[0]->get_attribute ('wref'), $x] if defined $x;
      } elsif ($ln eq 'small') {
        return ['small', parse_value $ctx_def, $value[0]->child_nodes->to_a];
      }
      return ['unparsed', $value[0]->outer_html];
    } elsif ($value[0]->node_type == 3) {
      return ['string', $value[0]->text_content];
    }
  }

  if (not grep { $_->node_type == 1 } @value) {
    return ['string', join '', map { $_->text_content } @value];
  } elsif (@value) {
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

sub apply_filters ($$) {
  my ($def, $v) = @_;

  for my $filter_name (@{$def->{filters} or []}) {
    my $filter = $FilterDefs->{$filter_name};
    unless (defined $filter) {
      warn "Filter |$filter_name| not defined";
      next;
    }
    $v = $filter->($def, $v);
    last unless defined $v;
  }

  for my $filter_name (@{$def->{string_filters} or []}) {
    last unless defined $v and ref $v eq 'ARRAY' and $v->[0] eq 'string';
    my $filter = $StringFilterDefs->{$filter_name};
    unless (defined $filter) {
      warn "String filter |$filter_name| not defined";
      next;
    }
    my $w = $filter->($def, $v->[1]);
    $v = $w if defined $w;
  }

  return $v;
} # apply_filters

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
          next unless defined $v;

          $v = apply_filters {filters => $sec_def->{item_filters},
                                  string_filters => $sec_def->{item_string_filters}}, $v;
          next unless defined $v;
          
          push @{$d->{items}}, $v;
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