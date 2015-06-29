use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->child ('t_deps/modules/*/lib');
use AnyEvent;
use Promise;
use Promised::Plackup;
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

my $root_path = path (__FILE__)->parent->parent->absolute;

my $mwx = Promised::Plackup->new;
$mwx->plackup ($root_path->child ('plackup'));
$mwx->set_option ('--server' => 'Twiggy');
$mwx->set_option ('--app' => $root_path->child ('bin/server.psgi'));

my @page = ('Perl');
my $p1 = 'p';
my $p2 = 'ja';

#$mwx->envs->{WEBUA_DEBUG} = 0;

print "1..1\n";

my $cv = AE::cv;
Promise->all ([
  $mwx->start,
  undef,
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
    print ref $data->{Perl} eq 'HASH' ? "ok 1\n" : "not ok 1\n";
  });
})->then (sub {
  return $mwx->stop;
})->then (sub {
  $cv->send;
}, sub {
  $cv->croak ($_[0]);
});

$cv->recv;
