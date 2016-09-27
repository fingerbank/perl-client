package fingerbank::DB;

=head1 NAME

fingerbank::DB

=head1 DESCRIPTION

Databases related interaction class

=cut

use Moose;
use namespace::autoclean;

use File::Copy qw(copy move);
use JSON;
use POSIX qw(strftime);

use fingerbank::Config;
use fingerbank::Constant qw($TRUE $FALSE);
use fingerbank::FilePath qw($INSTALL_PATH $LOCAL_DB_FILE $UPSTREAM_DB_FILE %SCHEMA_DBS);
use fingerbank::Log;
use fingerbank::Schema::Local;
use fingerbank::Schema::Upstream;
use fingerbank::Util qw(is_success is_error is_disabled);

has 'schema'        => (is => 'rw', isa => 'Str');
has 'handle'        => (is => 'rw', isa => 'Object');
has 'status_code'   => (is => 'rw', isa => 'Int');
has 'status_msg'    => (is => 'rw', isa => 'Str');

our @schemas = ('Local', 'Upstream');

our %_HANDLES = ();

=head1 OBJECT STATUS

=head2 isError

Returns whether or not the object status is erronous

=cut

sub isError {
    my ( $self ) = @_;
    return is_error($self->status_code);
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

=head1 METHODS

=head2 BUILD

=cut


sub BUILD {
    my ( $self ) = @_;
    my $logger = fingerbank::Log::get_logger;

    my $schema = $self->schema;

    $logger->trace("Requesting schema '$schema' DB handle");

    # Check if the requested schema is a valid one
    my %schemas = map { $_ => 1 } @schemas;
    if ( !exists($schemas{$schema}) ) {
        $self->status_code($fingerbank::Status::INTERNAL_SERVER_ERROR);
        $self->status_msg("Requested schema '$schema' does not exists");
        $logger->warn($self->status_msg);
        return;
    }

    # Test requested schema DB file validity
    return if is_error($self->_test);

    my $file_path = $SCHEMA_DBS{$schema};

    my $file_timestamp = ( stat($file_path) )[9];

    if( $_HANDLES{$schema} && $file_timestamp <= $_HANDLES{$schema}->{timestamp} ){
        $self->handle($_HANDLES{$schema}->{handle});
        return;
    }

    $logger->info("Database $file_path was changed or handles weren't initialized. Creating handle.");

    # Returning the requested schema db handle
    my $handle = "fingerbank::Schema::$schema"->connect("dbi:SQLite:".$file_path);
    $handle->{AutoInactiveDestroy} = $TRUE;
    $self->handle($handle);

    $_HANDLES{$schema} = { handle => $self->handle(), timestamp => $file_timestamp };

    return;
}

=head2 _test

Not meant to be used outside of this class

=cut

sub _test {
    my ( $self ) = @_;
    my $logger = fingerbank::Log::get_logger;

    my $schema = $self->schema;

    my $database_path = $INSTALL_PATH . "db/";
    my $database_file = fingerbank::Util::get_database_path($schema);

    $logger->trace("Testing '$schema' database");

    # Check if requested schema DB exists and is "valid"
    if ( (!-e $database_file) || (-z $database_file) ) {
        $self->status_code($fingerbank::Status::INTERNAL_SERVER_ERROR);
        $self->status_msg("Requested schema '$schema' DB file does not seems to be valid");
        $logger->error($self->status_msg);
        return $self->status_code;
    }

    # Check for read / write permissions with the effective uid/gid
    if ( (!-r $database_path) || (!-w $database_path) || (!-r $database_file) || (!-w $database_file) ) {
        $self->status_code($fingerbank::Status::INTERNAL_SERVER_ERROR);
        $self->status_msg("Requested schema '$schema' DB file does not seems to have the right permissions");
        $logger->error($self->status_msg);
        return $self->status_code;
    }

    $self->status_code($fingerbank::Status::OK);
    return $self->status_code;
}

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

    ($status, $status_msg) = fingerbank::Util::update_file( ('download_url' => $download_url, 'destination' => $destination, %params) );

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

    my $db = fingerbank::DB->new(schema => 'Local');
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

__PACKAGE__->meta->make_immutable;

1;
