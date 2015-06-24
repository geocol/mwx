# -*- perl -*-
use strict;
use warnings;
use MWX::Web;

$ENV{LANG} = 'C';
$ENV{TZ} = 'UTC';

return MWX::Web->psgi_app;

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
