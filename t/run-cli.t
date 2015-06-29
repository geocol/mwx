use strict;
use warnings;
use Path::Tiny;
use JSON::PS;

print "1..1\n";

my $root_path = path (__FILE__)->parent->parent->absolute;

my $json = `perl \Q$root_path/bin/extract-from-pages.pl\E Ruby`;
my $data = json_bytes2perl $json;

if (ref $data->{Ruby} eq 'HASH') {
  print "ok 1\n";
} else {
  print "not ok 1\n";
}
