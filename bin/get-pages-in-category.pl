use strict;
use warnings;
use Path::Tiny;
use Encode;
use AnyEvent;
use Promise;
use Promised::Plackup;
use Promised::File;
use Web::UserAgent::Functions qw(http_post);
use Wanage::URL;
use JSON::PS;

sub get_text ($$$$) {
  my ($host, $p1, $p2, $p3) = @_;
  return Promise->new (sub {
    my ($ok, $ng) = @_;
    http_post
        url => (sprintf q<http://%s/%s/%s/%s/categorymembers.txt>,
                    $host,
                    percent_encode_c $p1,
                    percent_encode_c $p2,
                    percent_encode_c $p3),
        params => {
        },
        timeout => 100,
        anyevent => 1,
        cb => sub {
          my $res = $_[1];
          if ($res->code == 200) {
            $ok->(decode 'utf-8', $res->content);
          } else {
            $ng->($res->code);
          }
        };
  });
} # get_text

my @page = map { decode 'utf-8', $_ } @ARGV;
@page or die "Usage: $0 [OPTIONS] page-name\n";

my $root_path = path (__FILE__)->parent->parent->absolute;

my $mwx = Promised::Plackup->new;
$mwx->plackup ($root_path->child ('plackup'));
$mwx->set_option ('--host' => '127.0.0.1');
$mwx->set_option ('--server' => 'Twiggy');
$mwx->set_option ('--app' => $root_path->child ('bin/server.psgi'));

my $p1 = 'p';
my $p2 = 'ja';

#$mwx->envs->{WEBUA_DEBUG} = 0;

my $cv = AE::cv;
Promise->all ([
  $mwx->start,
])->then (sub {
  my $host = $mwx->get_host;

  my $data = {};

  my $get; $get = sub {
    my $page = shift @page or return;
    return get_text ($host, $p1, $p2, $page)->then (sub {
      my $text = $_[0];
      $data->{$page} = [sort { $a cmp $b } grep { length } split /\x0A/, $text];
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
