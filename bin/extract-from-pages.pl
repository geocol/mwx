use strict;
use warnings;
use Path::Tiny;
use Encode;
use Getopt::Long;
use AnyEvent;
use Promise;
use Promised::Plackup;
use Promised::File;
use Web::UserAgent::Functions qw(http_post);
use Wanage::URL;
use JSON::PS;

sub get_json ($$$$$) {
  my ($host, $p1, $p2, $p3, $rules) = @_;
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    http_post
        url => (sprintf q<http://%s/%s/%s/%s/extracted.json>,
                    $host,
                    percent_encode_c $p1,
                    percent_encode_c $p2,
                    percent_encode_c $p3),
        params => {
          rules => $rules
        },
        anyevent => 1,
        cb => sub {
          my $res = $_[1];
          if ($res->code == 200) {
            $ok->(json_bytes2perl $res->content);
          } else {
            $ng->($res->code);
          }
        };
  });
} # get_json

my $RulesFileName;
GetOptions (
  '--rules-file-name=s' => \$RulesFileName,
) or die "Usage: $0 [OPTIONS] page-name...\n";

my @page = map { decode 'utf-8', $_ } @ARGV;
@page or die "Usage: $0 [OPTIONS] page-name...\n";

my $root_path = path (__FILE__)->parent->parent->absolute;

my $mwx = Promised::Plackup->new;
$mwx->plackup ($root_path->child ('plackup'));
$mwx->set_option ('--server' => 'Twiggy');
$mwx->set_option ('--app' => $root_path->child ('bin/server.psgi'));

my $p1 = 'p';
my $p2 = 'ja';

my ($rules_path, $rules_file);
if (defined $RulesFileName) {
  $rules_path = path ($RulesFileName);
  $rules_file = Promised::File->new_from_path ($rules_path);
}

#$mwx->envs->{WEBUA_DEBUG} = 0;

my $cv = AE::cv;
Promise->all ([
  $mwx->start,
  defined $rules_file ? $rules_file->read_char_string : undef,
])->then (sub {
  my $host = $mwx->get_host;
  my $rules = $_[0]->[1];

  my $data = {};

  my $get; $get = sub {
    my $page = shift @page or return;
    return get_json ($host, $p1, $p2, $page, $rules)->then (sub {
      my $json = $_[0];
      $data->{$page} = $json;
      return $get->();
    });
  }; # $get

  return $get->()->then (sub {
    print perl2json_bytes_for_record $data;
  });
})->then (sub {
  return $mwx->stop;
})->then (sub {
  $cv->send;
}, sub {
  $cv->croak ($_[0]);
});

$cv->recv;
