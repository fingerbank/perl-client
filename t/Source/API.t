#!/usr/bin/perl -w

use strict;
use warnings;
use diagnostics;

use lib 't';
use lib 'lib';

use Test::More;
use Test::Deep;
use Data::Dumper;
use Data::Compare;

BEGIN {
    use setup_tests;
}

use fingerbank::Util qw(is_success);
use fingerbank::Config;

use_ok('fingerbank::Source::API');

my $source = fingerbank::Source::API->new();

my ($status, $result);

if($ENV{FINGERBANK_KEY}){
    my $Config = fingerbank::Config::get_config();
    my $previous_key = $Config->{upstream}->{api_key};
    fingerbank::Config::write_config( { upstream => { api_key => $ENV{FINGERBANK_KEY} } } );

# test exact matching
    ($status, $result) = $source->match({dhcp_fingerprint => "1,121,3,6,15,119,252"});

    ok(is_success($status),
        "Can successfully interogate upstream API ($status)");

    ok($result->{SOURCE} eq "Upstream",
        "Result is coming from the Upstream source");
    
    fingerbank::Config::write_config( { upstream => { api_key => $previous_key } } );
}
else {
    print STDERR "Can't run extended tests for API source as no key is available \n";
}

done_testing();

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2015 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.            

=cut

