package MWX::Web;
use strict;
use warnings;
use Promise;
use Wanage::HTTP;
use Warabe::App;
use Web::DOM::Document;
use Text::MediaWiki::Parser;
use AnyEvent::MediaWiki::Source;

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
  if ($k1 eq 'd') {
    return AnyEvent::MediaWiki::Source->new_wiktionary_by_lang ($k2);
  } elsif ($k1 eq 'p') {
    return AnyEvent::MediaWiki::Source->new_wikipedia_by_lang ($k2);
  } else {
    return undef;
  }
} # _wp

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

sub main ($$) {
  my ($class, $app) = @_;
  my $path = $app->path_segments;

  # /{k1}/{k2}/{name}/{text|xml}
  if (@$path == 4 and
      ($path->[3] eq 'text' or $path->[3] eq 'xml')) {
    my $name = _name $path->[2];
    my $wp = _wp $path->[0], $path->[1]
        or $app->throw_error (404, reason_phrase => 'Wiki not found');
    return Promise->from_cv ($wp->get_source_text_by_name_as_cv ($name))->then (sub {
      return $app->send_error (404, reason_phrase => 'Page not found')
          unless defined $_[0];
      if ($path->[3] eq 'xml') {
        my $doc = _parse $name, $_[0];
        $app->http->set_response_header ('Content-Type' => 'text/xml; charset=utf-8');
        $app->http->send_response_body_as_text ($doc->inner_html);
        $app->http->close_response_body;
      } else { # text
        $app->send_plain_text ($_[0]);
      }
    });
  }

  return $app->send_error (404);
} # main

1;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
