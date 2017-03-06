package fingerbank::DB;

=head1 NAME

fingerbank::DB

=head1 DESCRIPTION

Databases related interaction class

=cut

use Moose;

use File::Copy qw(copy move);
use JSON;
use POSIX qw(strftime);

use fingerbank::Config;
use fingerbank::Constant qw($TRUE $FALSE $ALL_SCHEMAS_KW $LOCAL_SCHEMA $UPSTREAM_SCHEMA);
use fingerbank::FilePath qw($INSTALL_PATH $LOCAL_DB_FILE $UPSTREAM_DB_FILE %SCHEMA_DBS);
use fingerbank::Log;
use fingerbank::Schema::Local;
use fingerbank::Schema::Upstream;
use fingerbank::Util qw(is_success is_error is_disabled is_enabled);
use fingerbank::DB;

has 'schema'        => (is => 'rw');
has 'handle'        => (is => 'rw', builder => 'build_handle', lazy => 1);
has 'status_code'   => (is => 'rw');
has 'status_msg'    => (is => 'rw');

our @schemas = ($LOCAL_SCHEMA, $UPSTREAM_SCHEMA);

our %_HANDLES = ();

=head1 OBJECT STATUS

=head2 isError

Returns whether or not the object status is erronous

=cut

sub isError {
    my ( $self ) = @_;
    return !defined($self->status_code) || is_error($self->status_code);
}

=head2 isSuccess

Returns whether or not the object status is successful

=cut

sub isSuccess {
    my ( $self ) = @_;
    return is_success($self->status_code);
}

=head2 statusCode

Returns the object status code

=cut

sub statusCode {
    my ( $self ) = @_;
    return $self->status_code;
}

=head2 statusMsg

Returns the object status message

=cut

sub statusMsg {
    my ( $self ) = @_;
    return $self->status_msg;
}

=head2 BUILD

Initialize the handle after building the object

=cut

sub BUILD {
    my ($self) = @_;
    # Accessing the handle once we completed the initialization
    $self->handle;
}

=head2 build_handle

Meant to be overriden by child classes

=cut

sub build_handle {}

=head2 update_upstream

Update the existing 'upstream' database by taking care of backing up the current one

=cut

sub update_upstream {
    my ( %params ) = @_;
    my $logger = fingerbank::Log::get_logger;

    my ( $status, $status_msg );

    my $Config = fingerbank::Config::get_config;

    my $download_url    = ( exists($params{'download_url'}) && $params{'download_url'} ne "" ) ? $params{'download_url'} : $Config->{'upstream'}{'db_url'};
    my $destination     = ( exists($params{'destination'}) && $params{'destination'} ne "" ) ? $params{'destination'} : $UPSTREAM_DB_FILE;

    ($status, $status_msg) = fingerbank::Util::update_file( (
            'download_url' => $download_url, 
            'destination' => $destination, 
            'force_md5_check' => is_enabled($Config->{upstream}{db_download_force_md5_check}),
            %params
    ) );

    fingerbank::Util::cleanup_backup_files($destination, $Config->{upstream}{sqlite_db_retention});

    return ( $status, $status_msg )
}

=head2 submit_unknown

=cut

sub submit_unknown {
    my ( $self ) = @_;
    my $logger = fingerbank::Log::get_logger;

    my ( $status, $status_msg );

    my $Config = fingerbank::Config::get_config;

    # Are we configured to do so ?
    my $record_unmatched = $Config->{'query'}{'record_unmatched'};
    if ( is_disabled($record_unmatched) ) {
        $status = $fingerbank::Status::NOT_IMPLEMENTED;
        $status_msg = ("Not configured to record unmatched parameters. Cannot submit so skipping");
        $logger->debug($status_msg);
        return ( $status, $status_msg );
    }

    # Is an API key configured ?
    if ( !fingerbank::Config::is_api_key_configured ) {
        $status = $fingerbank::Status::UNAUTHORIZED;
        $status_msg = "Can't communicate with Fingerbank project without a valid API key.";
        $logger->warn($status_msg);
        return ( $status, $status_msg );
    }

    $logger->debug("Attempting to submit unmatched parameters to upstream Fingerbank project");

    require fingerbank::DB_Factory;
    my $db = fingerbank::DB_Factory->instantiate(schema => $LOCAL_SCHEMA);
    if ( $db->isError ) {
        $status = $fingerbank::Status::INTERNAL_SERVER_ERROR;
        $status_msg = "Cannot read from 'Unmatched' table in schema 'Local'";
        $logger->warn($status_msg . ". DB layer returned '" . $db->statusCode . " - " . $db->statusMsg . "'");
        return ( $status, $status_msg );
    }

    my $resultset = $db->handle->resultset('Unmatched')->search({ 'submitted' => $FALSE }, { columns => ['id', 'type', 'value'], order_by => { -asc => 'id' } });

    my ( $id, %data );
    foreach my $entry ( $resultset ) {
        while ( my $row = $entry->next ) {
            push ( @{ $data{$row->type} }, $row->value );
        }
    }

    my $ua = fingerbank::Util::get_lwp_client();
    $ua->timeout(10);  # A submit query should not take more than 10 seconds
    my $submitted_data = encode_json(\%data);

    my $req = HTTP::Request->new( POST => $Config->{'upstream'}{'submit_url'}.$Config->{'upstream'}{'api_key'} );
    $req->content_type('application/json');
    $req->content($submitted_data);

    my $res = $ua->request($req);

    if ( $res->is_success ) {
        $status = $fingerbank::Status::OK;
        $resultset->update( { 'submitted' => $TRUE } );
        $status_msg = "Successfully submitted unmatched arguments to upstream Fingerbank project";
        $logger->info($status_msg);
    } else {
        $status = $fingerbank::Status::INTERNAL_SERVER_ERROR;
        $status_msg = "An error occured while submitting unmatched arguments to upstream Fingerbank project";
        $logger->warn($status_msg . ": " . $res->status_line);
    }

    return ( $status, $status_msg );
}

=head2 get_schemas

Get the schema(s) to be used based on the parameter provided.
Will return all schemas if the parameter is undefined or is equals to $ALL_SCHEMAS_KW

Otherwise, will return the schema passed as a parameter.

=cut

sub get_schemas {
    my ($class, $schema) = @_;

    # From which schema do we want the results
    my @schemas = ( defined($schema) && $schema ne $ALL_SCHEMAS_KW ) ? ($schema) : @fingerbank::DB::schemas;

    return @schemas
}

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2016 Inverse inc.

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

__PACKAGE__->meta->make_immutable;

1;
