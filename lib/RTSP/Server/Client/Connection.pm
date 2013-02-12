# This class represents a client connection, which can request streams
# of video

package RTSP::Server::Client::Connection;

use Moose;
    with 'RTSP::Server::Connection';

use namespace::autoclean;
use Socket;
use Socket6;

has 'client_sockets' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
);

# map of stream_id -> stream
has 'streams' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
);

around 'public_options' => sub {
    my ($orig, $self) = @_;

    return ($self->$orig, qw/SETUP PLAY STOP/);
};

before 'teardown' => sub {
    my ($self) = @_;

    $self->finish;
};

sub play {
    my ($self) = @_;

    # find requested mount
    my $mount = $self->get_mount;
    unless ($mount) {
        $self->not_found;
        return;
    }

    # send range if available
    my $range = $mount->range;
    if ($range) {
        $self->add_resp_header('Range', $range);
    }

    # TODO: check auth

    $self->push_ok;
}

sub stop {
    my ($self) = @_;

    $self->finish;

    $self->push_ok;
}

sub setup {
    my ($self) = @_;

    if ($self->server->client_count > $self->server->max_clients) {
        $self->info("Rejecting client: maximum clients (" .
                    $self->server->max_clients . ") reached");

        # 453 really is 'Not Enough Bandwidth'
        return $self->push_response(453, "Maximum Clients Reached");
    }

    my $mount_path = $self->get_mount_path
        or return $self->bad_request;

    my ($mount, $stream_id) = $self->get_mount
        or return $self->not_found;

    $stream_id ||= 0;
    $self->debug("SETUP stream id $stream_id");

    # should have transport header
    my $transport = $self->get_req_header('Transport')
        or return $self->bad_request;

    # parse client ports out of transport header
    my ($client_rtp_start_port, $client_rtp_end_port) =
        $transport =~ m/client_port=(\d+)(?:\-(\d+))/smi;

    unless ($client_rtp_start_port) {
        $self->warn("Failed to find client RTP start port in SETUP request");
        return $self->bad_request;
    }

    # register client with stream
    my $stream = $mount->get_stream($stream_id)
        or return $self->not_found;

    my $local_port = $self->next_rtp_start_port;

    # create UDP socket for this stream
    my($name, $alias, $udp_proto) = AnyEvent::Socket::getprotobyname('udp');
    socket my($sock), $self->addr_family, SOCK_DGRAM, $udp_proto;
    AnyEvent::Util::fh_nonblocking $sock, 1;
    my ($local, $dest);
    if ($self->addr_family == AF_INET) {
        $local = sockaddr_in($local_port, Socket::inet_aton($self->local_address));
        $dest = sockaddr_in($client_rtp_start_port, Socket::inet_aton($self->client_address));
    } elsif ($self->addr_family == AF_INET6) {
        $local = sockaddr_in6($local_port, Socket6::inet_pton(AF_INET6, $self->local_address));
        $dest = sockaddr_in6($client_rtp_start_port, Socket6::inet_pton(AF_INET6, $self->client_address));
    }
    bind $sock, $local;
    unless (connect $sock, $dest) {
        $self->error("Failed to create client socket on port $client_rtp_start_port: $!");
        return $self->internal_server_error;
    }

    $self->client_sockets->{$stream_id} = $sock;
    $stream->add_client($self);

    # create UDP socket for the RTCP packets
    socket my($sock_rtcp), $self->addr_family, SOCK_DGRAM, $udp_proto;
    AnyEvent::Util::fh_nonblocking $sock_rtcp, 1;
    if ($self->addr_family == AF_INET) {
        $local = sockaddr_in($local_port + 1, Socket::inet_aton($self->local_address));
        $dest = sockaddr_in($client_rtp_end_port, Socket::inet_aton($self->client_address));
    } elsif ($self->addr_family == AF_INET6) {
        $local = sockaddr_in6($local_port + 1, Socket6::inet_pton(AF_INET6, $self->local_address));
        $dest = sockaddr_in6($client_rtp_end_port, Socket6::inet_pton(AF_INET6, $self->client_address));
    }
    bind $sock_rtcp, $local;
    unless (connect $sock_rtcp, $dest) {
        $self->error("Failed to create client socket on port $client_rtp_end_port: $!");
        return $self->internal_server_error;
    }

    $self->client_sockets->{$stream_id . "rtcp"} = $sock_rtcp;

    # add our RTP ports to transport header response
    my $port_range = $local_port . '-' . ($local_port + 1);
    $self->add_resp_header("Transport", "$transport;server_port=$port_range");

    $self->push_ok;
}

sub send_packet {
    my ($self, $stream_id, $pkt) = @_;

    my $sock = $self->client_sockets->{$stream_id}
    or return;
    my $type_byte = ord(substr($pkt, 1, 1));
    $sock = $self->client_sockets->{$stream_id . "rtcp"} if ($type_byte >= 200 && $type_byte <= 204);

    return send $sock, $pkt, 0;
}

sub finish {
    my ($self) = @_;

    my $mount = $self->get_mount;
    $mount->remove_client($self) if $mount;

    $self->streams({});

    my @sockets = values %{ $self->client_sockets };
    foreach my $sock (@sockets) {
        shutdown $sock, 1;  # done writing
    }

    $self->client_sockets({});
}

sub DEMOLISH {
    my ($self) = @_;

    $self->finish;
}

__PACKAGE__->meta->make_immutable;

