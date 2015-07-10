use strict;
use warnings;
use Path::Tiny;
use JSON::PS;

print "1..1\n";

my $root_path = path (__FILE__)->parent->parent->absolute;

my $json = `perl \Q$root_path/bin/get-pages-in-category.pl\E Category:日本の町・字のテンプレート`;
my $data = json_bytes2perl $json;

use utf8;
if (ref $data->{"Category:日本の町・字のテンプレート"} eq 'ARRAY') {
  print "ok 1\n";
} else {
  print "not ok 1\n";
}
