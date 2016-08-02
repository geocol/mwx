package MWX::Web;
use strict;
use warnings;
use Path::Tiny;
use Path::Class;
use Promise;
use Promised::File;
use JSON::PS;
use Wanage::URL;
use Wanage::HTTP;
use Warabe::App;
use Web::DOM::Document;
use Text::MediaWiki::Parser;
use AnyEvent::MediaWiki::Source;
use Temma::Parser;
use Temma::Processor;
use MWX::Parser;
use MWX::Extractor;
use Web::UserAgent::Functions qw(http_get);
use Web::Encoding qw(decode_web_utf8);

my $KeyMapping = {};
if (defined $ENV{MWX_KEY_MAPPING}) {
  my $path = path ($ENV{MWX_KEY_MAPPING});
  my $base_path = $path->parent;
  my $json = json_bytes2perl $path->slurp;
  if (defined $json and ref $json eq 'HASH') {
    for my $k1 (keys %$json) {
      if (ref $json->{$k1} eq 'HASH') {
        for my $k2 (keys %{$json->{$k1}}) {
          if (ref $json->{$k1}->{$k2} eq 'HASH') {
            $KeyMapping->{$k1}->{$k2} = {
              cache_d => dir ($json->{$k1}->{$k2}->{cache_dir_name})->absolute ($base_path),
              dump_f => file ($json->{$k1}->{$k2}->{dump_file_name})->absolute ($base_path),
            };
          }
        }
      }
    }
  }
}

my $UpstreamURLPrefix = $ENV{MWX_UPSTREAM_URL_PREFIX};

sub _parse ($$) {
  my $doc = new Web::DOM::Document;
  my $parser = Text::MediaWiki::Parser->new;
  $parser->parse_char_string ($_[1] => $doc);
  $doc->title ($_[0]);
  return $doc;
} # _parse

sub _name ($) {
  my $s = shift;
  $s =~ s/\A\s+//;
  $s =~ s/\s+\z//;
  $s =~ s/\s+/_/;
  $s =~ s/^([a-z])/uc $1/ge;
  $s =~ s/(_[a-z])/uc $1/ge;
  $s =~ tr/_/ /;
  return $s;
} # _name

sub _wp ($$) {
  my ($k1, $k2) = @_;
  my $mw;
  if ($k1 eq 'd') {
    $mw = AnyEvent::MediaWiki::Source->new_wiktionary_by_lang ($k2);
  } elsif ($k1 eq 'p') {
    $mw = AnyEvent::MediaWiki::Source->new_wikipedia_by_lang ($k2);
  } else {
    return undef;
  }

  if ($KeyMapping->{$k1}->{$k2}) {
    my $mw2 = AnyEvent::MediaWiki::Source->new_from_dump_f_and_cache_d
        ($KeyMapping->{$k1}->{$k2}->{dump_f},
         $KeyMapping->{$k1}->{$k2}->{cache_d});
    $mw2->top_url ($mw->top_url);
    return $mw2;
  } else {
    return $mw;
  }
} # _wp

sub _get_upstream_as_cv ($$$$) {
  my ($k1, $k2, $name, $type) = @_;
  my $cv = AE::cv;
  http_get
      url => (sprintf q<%s/%s/%s/%s/%s>, $UpstreamURLPrefix, percent_encode_c $k1, percent_encode_c $k2, percent_encode_c $name, $type),
      timeout => 60*10,
      anyevent => 1,
      cb => sub {
        if ($_[1]->code == 200) {
          $cv->send (decode_web_utf8 $_[1]->content);
        } elsif ($_[1]->code < 500) {
          $cv->send (undef);
        } else {
          $cv->croak ($_[1]->as_string);
        }
      };
  return $cv;
} # _get_upstream_as_cv

sub psgi_app ($) {
  return sub {
    my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
    my $app = Warabe::App->new_from_http ($http);

    # XXX accesslog
    warn sprintf "Access: [%s] %s %s\n",
        scalar gmtime, $app->http->request_method, $app->http->url->stringify;

    return $app->execute_by_promise (sub {
      #XXX
      #my $origin = $app->http->url->ascii_origin;
      #if ($origin eq $app->config->{web_origin}) {
        return __PACKAGE__->main ($app);
      #} else {
      #  return $app->send_error (400, reason_phrase => 'Bad |Host:|');
      #}
    });
  };
} # psgi_app

my $RulesPath = path (__FILE__)->parent->parent->parent->child ('rules');
my $PageCache = {};
my $MembersCache = {};

sub main ($$) {
  my ($class, $app) = @_;
  my $path = $app->path_segments;

  # /{k1}/{k2}/{name}/{text|xml|extracted.json|open}
  if (@$path == 4 and
      ($path->[3] eq 'text' or
       $path->[3] eq 'xml' or
       $path->[3] eq 'extracted.json' or
       $path->[3] eq 'open')) {
    my $name = _name $path->[2];
    my $wp = _wp $path->[0], $path->[1]
        or $app->throw_error (404, reason_phrase => 'Wiki not found');
    if ($path->[3] eq 'open') {
      $name =~ s/ /_/g;
      return $app->send_redirect ($wp->top_url . 'wiki/' . percent_encode_c $name);
    }

    return Promise->resolve (do {
      if (exists $PageCache->{$path->[0], $path->[1], $name}) {
        $PageCache->{$path->[0], $path->[1], $name}; # or undef
      } else {
        Promise->from_cv ($UpstreamURLPrefix ? _get_upstream_as_cv ($path->[0], $path->[1], $name, 'text') : $wp->get_source_text_by_name_as_cv ($name))->then (sub {
          return $PageCache->{$path->[0], $path->[1], $name} = $_[0]; # or undef
        });
      }
    })->then (sub {
      return $app->send_error (404, reason_phrase => 'Page not found')
          unless defined $_[0];

      if ($path->[3] eq 'text') {
        return $app->send_plain_text ($_[0]);
      }

      my $doc = _parse $name, $_[0];
      if ($path->[3] eq 'xml') {
        $app->http->set_response_header ('Content-Type' => 'text/xml; charset=utf-8');
        $app->http->send_response_body_as_text ($doc->inner_html);
        $app->http->close_response_body;
        return;
      }

      if ($path->[3] eq 'extracted.json') {
        return Promise->resolve->then (sub {
          my $rules = $app->text_param ('rules');
          if (defined $rules and length $rules) {
            my $parser = MWX::Parser->new;
            # XXX error
            return $parser->parse_char_string ($rules);
          }
          my $rules_name = $app->text_param ('rules_name');
          if (defined $rules_name and length $rules_name) {
            if ($rules_name =~ /\A[0-9a-z_-]+\z/) {
              my $path = Promised::File->new_from_path ($RulesPath->child ("$rules_name.txt"));
              return $path->is_file->then (sub {
                if ($_[0]) {
                  return $path->read_char_string->then (sub {
                    my $parser = MWX::Parser->new;
                    # XXX error
                    return $parser->parse_char_string ($_[0]);
                  });
                } else {
                  return $app->throw_error (400, reason_phrase => 'Bad |rules_name|');
                }
              });
            } else {
              return $app->throw_error (400, reason_phrase => 'Bad |rules_name|');
            }
          }
          return undef;
        })->then (sub {
          my $rules = $_[0];
          return MWX::Extractor->process ($doc, $rules)->then (sub {
            $app->http->set_response_header ('Content-Type' => 'application/json; charset=utf-8');
            $app->http->send_response_body_as_text (perl2json_chars $_[0]);
            $app->http->close_response_body;
          });
        });
      }

      die;
    });

  # /{k1}/{k2}/{name}/categorymembers.txt
  } elsif (@$path == 4 and $path->[3] eq 'categorymembers.txt') {
    my $name = _name $path->[2];
    my $wp = _wp $path->[0], $path->[1]
        or $app->throw_error (404, reason_phrase => 'Wiki not found');
    
    return Promise->resolve (do {
      if (exists $MembersCache->{$path->[0], $path->[1], $name}) {
        $MembersCache->{$path->[0], $path->[1], $name}; # or undef
      } else {
        if ($UpstreamURLPrefix) {
          Promise->from_cv (_get_upstream_as_cv ($path->[0], $path->[1], $name, $path->[3]))->then (sub {
            return $MembersCache->{$path->[0], $path->[1], $name} = $_[0]; # or undef
          });
        } else {
          Promise->from_cv ($UpstreamURLPrefix ? _get_upstream_as_cv ($path->[0], $path->[1], $name, $path->[3]) : $wp->get_category_members_by_http_as_cv ($name))->then (sub {
            return $MembersCache->{$path->[0], $path->[1], $name} = defined $_[0] ? (join "\x0A", map { $_->{title} } @{$_[0]}) : $_[0];
          });
        }
      }
    })->then (sub {
      return $app->send_error (404, reason_phrase => 'Page not found')
          unless defined $_[0];
      return $app->send_plain_text ($_[0]);
    });
  }

  if (@$path == 1 and $path->[0] eq '') {
    # /
    return $class->temma ($app->http, 'index.html.tm', {});
  } elsif (@$path == 1 and $path->[0] eq 'xml') {
    # /xml
    return $class->temma ($app->http, 'xml.html.tm', {});
  } elsif (@$path == 1 and $path->[0] eq 'json') {
    # /json
    return $class->temma ($app->http, 'json.html.tm', {});
  }

  return $app->send_error (404);
} # main

my $TemplatesPath = path (__FILE__)->parent->parent->parent->child ('templates');

use Path::Class; # XXX
sub temma ($$$$) {
  my ($class, $http, $template_path, $args) = @_;
  $template_path = $TemplatesPath->child ($template_path);
  die "|$template_path| not found" unless $template_path->is_file;

  $http->set_response_header ('Content-Type' => 'text/html; charset=utf-8');
  my $fh = MWX::Web::TemmaPrinter->new_from_http ($http);
  my $ok;
  my $p = Promise->new (sub { $ok = $_[0] });

  my $doc = new Web::DOM::Document;
  my $parser = Temma::Parser->new;
  $parser->parse_f (file ($template_path) => $doc); # XXX blocking
  my $processor = Temma::Processor->new;
  $processor->process_document ($doc => $fh, ondone => sub {
    $http->close_response_body;
    $ok->();
  }, args => $args);

  return $p;
} # temma

package MWX::Web::TemmaPrinter;

sub new_from_http ($$) {
  return bless {http => $_[1]}, $_[0];
} # new_from_http

sub print ($$) {
  $_[0]->{value} .= $_[1];
  if (length $_[0]->{value} > 1024*10 or length $_[1] == 0) {
    $_[0]->{http}->send_response_body_as_text ($_[0]->{value});
    $_[0]->{value} = '';
  }
} # print

sub DESTROY {
  $_[0]->{http}->send_response_body_as_text ($_[0]->{value})
      if length $_[0]->{value};
} # DESTROY

1;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
