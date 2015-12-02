#!/usr/bin/perl -w

use strict;
use warnings;
use diagnostics;

use lib 'lib';

use Test::More;
use Test::Deep;
use Data::Dumper;
use Data::Compare;

use_ok('fingerbank::Model::Endpoint');

ok(my $endpoint = fingerbank::Model::Endpoint->new(name => "Windows Kernel Z", version => "1.0", score => 5, parents => ["Windows"]),
    "Can create an endpoint");

ok($endpoint->is_a("Windows"),
    "Endpoint is detected as a Windows based device");
ok(!$endpoint->is_a("Macintosh"),
    "Endpoint is not detected as a Macintosh");

ok($endpoint->isWindows(),
    "Enpoint responds correctly to isWindows");
ok(!$endpoint->isMacOS(),
    "Endpoint responds correctly to isMacOS");

my $json_result = <<"RESULT";
{
    "created_at": "2014-10-13T03:14:45.000Z",
    "device": {
        "created_at": "2014-09-09T15:09:51.000Z",
        "id": 33,
        "inherit": null,
        "mobile?": false,
        "name": "Microsoft Windows Vista/7 or Server 2008 (Version 6.0)",
        "parent_id": 1,
        "parents": [
            {
                "approved": true,
                "created_at": "2014-09-09T15:09:50.000Z",
                "id": 1,
                "inherit": null,
                "mobile": null,
                "name": "Windows",
                "parent_id": null,
                "submitter_id": null,
                "tablet": null,
                "updated_at": "2014-09-09T15:09:50.000Z"
            }
        ],
        "updated_at": "2014-09-09T15:09:52.000Z"
    },
    "id": 5733,
    "score": 50,
    "updated_at": "2014-11-13T17:39:36.000Z",
    "version": null
}
RESULT

use JSON;
my $result = decode_json($json_result);

$endpoint = fingerbank::Model::Endpoint->fromResult($result);

ok($endpoint->name eq "Microsoft Windows Vista/7 or Server 2008 (Version 6.0)",
    "Endpoint name is properly populated from result");

ok(!defined($endpoint->version),
    "Endpoint version is properly populated from result");

ok($endpoint->score eq 50,
    "Endpoint score is properly populated from result");

my $expected_parents = ["Windows"];
my ($ok, $stack) = Test::Deep::cmp_details($endpoint->parents, $expected_parents);

ok($ok,
    "Endpoint parents are properly populated from result");

$endpoint = fingerbank::Model::Endpoint->new(name => "Samsung Android", score => 0, version => undef);

$expected_parents = ["Generic Android", "Smartphones/PDAs/Tablets"];
($ok, $stack) = Test::Deep::cmp_details($endpoint->parents, $expected_parents);

ok($ok,
    "Endpoint parents are properly looked up when they are not passed to constructor");

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

