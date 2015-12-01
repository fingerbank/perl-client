package fingerbank::Source::LocalDB;

=head1 NAME

fingerbank::Source::LocalDB

=head1 DESCRIPTION

Source for interrogating the local Fingerbank databases (Upstream and Local)

=cut

use Moose;
extends 'fingerbank::Base::Source';

use namespace::autoclean;

use JSON;
use Module::Load;
use POSIX;

use fingerbank::Config;
use fingerbank::Constant qw($TRUE);
use fingerbank::Log;
use fingerbank::Model::Combination;
use fingerbank::Model::Device;
use fingerbank::Util qw(is_enabled is_disabled is_error is_success);

# The query keys required to fullfil a match
# - We load the appropriate module for each of the different query keys based on their name
# - We declare object attributes for each of the different query keys based on their name
foreach my $key ( @fingerbank::Constant::QUERY_PARAMETERS ) {
    load "fingerbank::Model::$key";
    has $key . '_value' => (is => 'rw', isa => 'Str', default => "");
    has $key . '_id'    => (is => 'rw', isa => 'Str', default => "");
}

has 'device_id' => (is => 'rw', isa => 'Str');
has 'combination_id' => (is => 'rw', isa => 'Str');
has 'combination_is_exact' => (is => 'rw', isa => 'Str');
has 'matched_schema' => (is => 'rw', isa => 'Str');


=head2 match

Check whether or not the arguments match this source

=cut

sub match {
    my ( $self, $args, $other_results ) = @_;
    my $logger = fingerbank::Log::get_logger;

    # Initialize status variables
    # We set the status to OK so we can proceed
    my ($status, $status_msg) = $fingerbank::Status::OK;

    # TODO: Review that part to make it less "hacky"
    $args->{'mac_vendor'} = $args->{'mac'};

    # We assign the value of each key to the corresponding object attribute (ie.: DHCP_Fingerprint_value)
    # Note: We must have all of the keys in the query, either with a value or with ''
    $logger->debug("Attempting to match a device with the following attributes:");
    foreach my $key ( @fingerbank::Constant::QUERY_PARAMETERS ) {
        my $concatenated_key = $key . '_value';
        $self->$concatenated_key($args->{lc($key)}) if ( defined($args->{lc($key)}) );
        $logger->debug("- $concatenated_key: '" . $self->$concatenated_key . "'");
    }

    ($status, $status_msg) = $self->_getQueryKeyIDs;
    ($status, $status_msg) = $self->_getCombinationID if ( is_success($status) );

    my $result;
    # Upstream is configured (an API key is configured and interrogate upstream is enabled) with an unexact match, we go upstream
    if ( !$self->{combination_is_exact} && fingerbank::Config::is_api_key_configured && fingerbank::Config::do_we_interrogate_upstream ) {
        $logger->info("Upstream is configured and unable to fullfil an exact match locally. Will ignore result from local database");
        return $fingerbank::Status::NOT_FOUND;
    } 
    # Either local match is exact or upstream is not configured, build local result
    else {
        $logger->info("Locally matched combination is exact. Build result") if $self->{combination_is_exact};
        $logger->info("Building the result locally");
        ( $status, $result ) = $self->_buildResult if ( is_success($status) );
    }

    if ( is_success($status) ) {
        $result->{device_id} = $result->{device}->{id};
        return ($status, $result);
    }

    $logger->warn("Unable to fullfil a match either locally or using upstream Fingerbank project.");
    return $fingerbank::Status::NOT_FOUND;
}

=head2 _buildResult

Not meant to be used outside of this class. Refer to L<fingerbank::Source::LocalDB::match>

=cut

sub _buildResult {
    my ( $self ) = @_;
    my $logger = fingerbank::Log::get_logger;

    my $result = {};

    # Get the combination info
    my ( $status, $combination ) = fingerbank::Model::Combination->read($self->combination_id);
    return $status if ( is_error($status) );

    foreach my $key ( keys %$combination ) {
        $result->{$key} = $combination->{$key};
    }

    # Get device info
    ( $status, my $device ) = fingerbank::Model::Device->read($combination->{device_id}, $TRUE);
    return $status if ( is_error($status) );

    foreach my $key ( keys %$device ) {
        $result->{device}->{$key} = $device->{$key};
    }

    # Tracking down from where the result is coming
    $result->{'SOURCE'} = "Local";
    $result->{'SCHEMA'} = $self->matched_schema;

    return ( $fingerbank::Status::OK, $result );
}


=head2 _getQueryKeyIDs

Not meant to be used outside of this class. Refer to L<fingerbank::Source::LocalDB::match>

=cut

sub _getQueryKeyIDs {
    my ( $self ) = @_;
    my $logger = fingerbank::Log::get_logger;

    foreach my $key ( @fingerbank::Constant::QUERY_PARAMETERS ) {
        my $concatenated_key = $key . '_value';
        $logger->debug("Attempting to find an ID for '$key' with value '" . $self->$concatenated_key . "'");

        my $query = {};
        $query->{'value'} = $self->$concatenated_key;

        # MAC_Vendor key is different in the way we store the values in the database. Need to handle it
        if ( $key eq 'MAC_Vendor' ) {
            if ( $query->{'value'} eq '' ) {
                $logger->debug("Attempting to find an ID for 'MAC_Vendor' with empty value. This is a special case. Returning 'NULL'");
                $self->{$key . '_id'} = 'NULL';
                next;
            }
            $query->{'mac'} = delete $query->{'value'}; # The 'value' column is the 'mac' column in this specific case
            my $mac = $query->{'mac'};
            $mac =~ s/[:|\s|-]//g;      # Removing separators
            $mac = lc($mac);            # Lowercasing
            $mac = substr($mac, 0, 6);  # Only keep first 6 characters (OUI)
            $query->{'mac'} = $mac;
            $logger->debug("Attempting to find an ID for '$key'. This is a special case. Using mangled value '$mac'");
        }

        my $model = "fingerbank::Model::$key";
        my $id = $self->cache->compute("$model\_".encode_json($query), sub { 
            my ($status, $result) = $model->find([$query, { columns => ['id'] }]);
            if ( is_error($status) ) {
                my $status_msg = "Cannot find any ID for '$key' with value '" . $self->$concatenated_key . "'";
                $logger->warn($status_msg);

                # We record the unmatched query key if configured to do so
                my $record_unmatched = fingerbank::Config::get_config('query', 'record_unmatched');
                $self->_recordUnmatched($key, $self->$concatenated_key) if is_enabled($record_unmatched);

                return ( $fingerbank::Status::NOT_FOUND, $status_msg );
            }
            return $result->id;
        });
    
        if($id){
            $self->{$key . '_id'} = $id;
        }
       
        $logger->debug("Found ID '" . $self->{$key . '_id'} . "' for '$key' with value '" . $self->$concatenated_key . "'");
    }

    return $fingerbank::Status::OK;
}

=head2 _getCombinationID

Not meant to be used outside of this class. Refer to L<fingerbank::Source::LocalDB::match>

=cut

sub _getCombinationID {
    my ( $self ) = @_;
    my $logger = fingerbank::Log::get_logger;

    # Building the query bindings
    # Those are the IDs for each query keys. Order is important since the SQL query is dependant
    # See L<fingerbank::Base::Schema::CombinationMatch>
    $logger->debug("Attempting to find a combination with the following ID(s):");
    my @bindings = ();
    foreach my $key ( @fingerbank::Constant::QUERY_PARAMETERS ) {
        my $concatenated_key = $key . '_id';
        push @bindings, $self->$concatenated_key;
        $logger->debug("Query - $concatenated_key: '" . $self->$concatenated_key . "'");
    }

    # Looking for best matching combination in schemas
    # Sorting by match is handled by the SQL query itself. See L<fingerbank::Base::Schema::CombinationMatch>
    foreach my $schema ( @fingerbank::DB::schemas ) {
        my $db = fingerbank::DB->new(schema => $schema);
        if ( $db->isError ) {
            $logger->warn("Cannot read from 'CombinationMatch' table in schema 'Local'. DB layer returned '" . $db->statusCode . " - " . $db->statusMsg . "'");
            return $fingerbank::Status::INTERNAL_SERVER_ERROR;
        }

        # If API is configured, we want an exact match to save us some time by avoiding a complex query
        my $resultset;
        if ( fingerbank::Config::is_api_key_configured && fingerbank::Config::do_we_interrogate_upstream ) {
            $resultset = $db->handle->resultset('CombinationMatchExact')->search({}, { bind => [ @bindings ] })->first;
        }
        # Otherwise, we proceed with the complex select query using a view and where / case clauses 
        else {
            my $id = $self->cache->compute("CombinationMatch_$schema\_".encode_json(\@bindings), sub { 
                my $result = $db->handle->resultset('CombinationMatch')->search({}, { bind => [ @bindings ] })->first;
                return $result ? $result->id : undef;
            });
            if($id) {
                $resultset = $db->handle->resultset('Combination')->search({id => $id})->first;
            }
        }

        if ( defined($resultset) ) {
            # Make sure combination found is valid (contains a device ID)
            if ( defined($resultset->device_id) && $resultset->device_id ne "" ) {
                $self->combination_id($resultset->id);
                $logger->info("Found combination ID '" . $self->combination_id . "' in schema '$schema'");
            } else {
                my $status_msg = "Found combination ID '" . $resultset->id . "' in schema '$schema' but combination does not contain a device ID";
                $logger->info($status_msg);
                return ( $fingerbank::Status::NOT_FOUND, $status_msg );
            }

            # Check if exact match
            my $matched_keys = 0;
            foreach ( @fingerbank::Constant::QUERY_PARAMETERS ) {
                my $concatenated_key = $_ . '_id';
                my $lc_concatenated_key = lc($concatenated_key);
                $logger->debug("ResultSet - $lc_concatenated_key: '" . $resultset->$lc_concatenated_key . "'");
                $matched_keys ++ if ( $resultset->$lc_concatenated_key eq $self->$concatenated_key || $resultset->$lc_concatenated_key eq '' );
            }
            my $exact_matched_keys = @fingerbank::Constant::QUERY_PARAMETERS;
            $self->combination_is_exact($TRUE) if ( $matched_keys == $exact_matched_keys );
            $self->matched_schema($schema);

            last if $self->combination_is_exact;
        }

        $logger->debug("No combination ID found in schema '$schema'");
    }

    if ( !defined($self->combination_id) ) {
        my $status_msg = "Cannot find any combination ID in any schemas";
        $logger->warn($status_msg);
        return ( $fingerbank::Status::NOT_FOUND, $status_msg );
    }

    return $fingerbank::Status::OK;
}

=head2 _recordUnmatched

Not meant to be used outside of this class. Refer to L<fingerbank::Source::LocalDB::match>

=cut

sub _recordUnmatched {
    my ( $self, $key, $value ) = @_;
    my $logger = fingerbank::Log::get_logger;

    # Are we configured to do so ?
    my $record_unmatched = fingerbank::Config::get_config('query', 'record_unmatched');
    if ( is_disabled($record_unmatched) ) {
        $logger->debug("Not configured to keep track of unmatched query keys. Skipping");
        return;
    }

    $logger->debug("Attempting to record the unmatched query key '$key' with value '$value' in the 'unmatched' table of 'Local' database");

    # We first check if we already have the entry, if so we simply increment the occurence number
    my $db = fingerbank::DB->new(schema => 'Local');
    if ( $db->isError ) {
        $logger->warn("Cannot read from 'Unmatched' table in schema 'Local'. DB layer returned '" . $db->statusCode . " - " . $db->statusMsg . "'");
        return;
    }

    my $resultset = $db->handle->resultset('Unmatched')->search({
        type    => { 'like', $key },
        value   => { 'like', $value},
    });

    # We do not have an existing entry for that query key. Creating a new one
    if ( $resultset eq 0 ) {
        $logger->info("New unmatched '$key' query key detected with value '$value'. Adding an entry to the 'unmatched' table of 'Local' database");
        my %args = (
            type => $key,
            value => $value,
            created_at => strftime("%Y-%m-%d %H:%M:%S", localtime(time)),
            updated_at => strftime("%Y-%m-%d %H:%M:%S", localtime(time)),
        );
        my $unmatched_key = $db->handle->resultset('Unmatched')->create(\%args);
    }

    # We have an existing entry for that query key. Incrementing the occurence number
    else {
        $logger->info("Existing unmatched '$key' query key detected with value '$value'. Incrementing the number of occurence");
        my $occurence = $resultset->first->occurence;
        $occurence ++;
        my %args = (
            updated_at  => strftime("%Y-%m-%d %H:%M:%S", localtime(time)),
            occurence   => $occurence,
        );
        my $unmatched_key = $db->handle->resultset('Unmatched')->update(\%args);
    }
}



=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2014 Inverse inc.

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
1;

