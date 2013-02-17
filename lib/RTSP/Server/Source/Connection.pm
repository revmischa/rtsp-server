# This class represents a source connection, which can publish to a
# video stream

package RTSP::Server::Source::Connection;

use Moose;
    with 'RTSP::Server::Connection';

use namespace::autoclean;
use RTSP::Server::RTPListener;
use RTSP::Server::Mount::Stream;

has 'rtp_listeners' => (
    is => 'rw',
    isa => 'ArrayRef[RTSP::Server::RTPListener]',
    default => sub { [] },
    lazy => 1,
);

around 'public_options' => sub {
    my ($orig, $self) = @_;

    return ($self->$orig, qw/SETUP ANNOUNCE RECORD/);
};

# cleanup
before 'teardown' => sub {
    my ($self) = @_;

    my $mount = $self->get_mount;

    if ($mount) {
        # TODO: notify clients connected to mount that it is closing

        # should make sure stream is unmounted
        $self->unmount;
    }

    $self->end_rtp_server;
};

sub start_rtp_server {
    my ($self) = @_;

    my $mount = $self->get_mount
        or return;

    $self->debug("Starting RTP listeners");
    my $ok = 0;

    foreach my $stream ($mount->streams) {
        $self->debug(" |-- stream " . $stream->index);

        foreach my $port ($stream->get_rtp_listen_ports) {
            $self->debug(" |---- port $port");

            my $listener = RTSP::Server::RTPListener->new(
                mount => $mount,
                stream => $stream,
                host => $self->local_address,
                addr_family => $self->addr_family,
                port => $port,
            );

            push @{ $self->rtp_listeners }, $listener;

            unless ($listener->listen) {
                $self->error("Failed to create RTP listener on port $port");
                return;
            }

            $ok = 1;
        }
    }

    return $ok;
}

sub end_rtp_server {
    my ($self) = @_;

    my $listeners = $self->rtp_listeners;
    return unless @$listeners;

    $self->debug("Shutting down RTP listeners");
    foreach my $listener (@$listeners) {
        $self->debug(" -> port " . $listener->port);
        $listener->close;
    }

    $self->rtp_listeners([]);
}

sub record {
    my ($self) = @_;

    my $mount = $self->get_mount;
    unless ($mount) {
        return $self->not_found;
    }

    $self->debug("Got record for mountpoint " . $mount->path);

    # save range if present
    my $range = $self->get_req_header('Range');
    $range ? $mount->range($range) : $mount->clear_range;

    if ($self->start_rtp_server) {
        $self->push_ok;
        $mount->mounted(1);
    } else {
        $self->not_found;
    }
}

sub announce {
    my ($self) = @_;

    # we should have SDP data in the body
    my $body = $self->body
        or return $self->bad_request;

    my $mount = $self->get_mount;

    if ($mount) {
        # mount is in use. return error.
        $self->info("Source attempting to announce mountpoint " .
                     $mount->path . ', but it is already in use');
        return $self->push_response(403, 'Forbidden');
    }

    $self->debug("Got source announcement for " . $self->req_uri);

    # create mountpoint
    my $mount_path = $self->get_mount_path($self->req_uri)
        or return $self->bad_request;

    $mount = $self->mount(
        path => $mount_path,
        sdp => $body,
    );

    unless ($mount) {
        $self->error("Failed to mount stream at $mount_path");
        return $self->bad_request;
    }

    $self->push_ok;

    # TODO: broadcast announcement to all connected clients
}

sub setup {
    my ($self) = @_;

    my $mount_path = $self->get_mount_path
        or return $self->not_found;

    # does a mount exist? RTSP spec (10.4) says a client can issue a
    # SETUP for an existing stream to change the params.
    my ($mount, $stream_id) = $self->get_mount;
    $self->debug("Got SETUP request for stream $stream_id");
    if ($mount && $mount->mounted) {
        # well, we don't support that yet.
        $self->debug("SETUP request for $mount_path, but the mountpoint is in use");
        return $self->push_response(455, 'Method Not Valid In This State');
    }

    # should have transport header
    my $transport = $self->get_req_header('Transport')
        or return $self->bad_request;

    $stream_id ||= 0;

    # create stream
    my $stream = $mount->get_stream($stream_id);
    unless ($stream) {
        $self->debug("Creating new stream $stream_id");

        $stream = RTSP::Server::Mount::Stream->new(
            rtp_start_port => $self->next_rtp_start_port,
            index => $stream_id,
        );
    }

    # add stream to mount
    $mount->add_stream($stream);

    # add our RTP ports to transport header response
    my $port_range = $stream->rtp_port_range;
    $self->add_resp_header("Transport", "$transport;server_port=$port_range");

    $self->push_ok;
}

__PACKAGE__->meta->make_immutable;

