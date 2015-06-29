use strict;
use warnings;
use Path::Tiny;
use MWX::Parser;
use JSON::PS;

my $path = path (shift);
my $parser = MWX::Parser->new;

warn perl2json_bytes_for_record $parser->parse_char_string ($path->slurp_utf8);
