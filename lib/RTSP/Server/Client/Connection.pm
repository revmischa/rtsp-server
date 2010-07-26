# This class represents a client connection, which can request streams
# of video

package RTSP::Server::Client::Connection;

use Moose;
    with 'RTSP::Server::Connection';

use namespace::autoclean;
use Socket;

has 'client_socket' => (
    is => 'rw',
    clearer => 'clear_client_socket',
);

# packed sock addr of client
has 'client_socket_dest' => (
    is => 'rw',
);

has 'client_rtp_port' => (
    is => 'rw',
    isa => 'Int',
);

around 'public_options' => sub {
    my ($orig, $self) = @_;

    return ($self->$orig, qw/SETUP PLAY STOP/);
};

before 'teardown' => sub {
    my ($self) = @_;

    $self->close_socket;
};

sub play {
    my ($self) = @_;

    # should have this from SETUP
    my $port = $self->client_rtp_port
        or return $self->bad_request;

    # find requested mount
    my $mount = $self->get_mount;
    unless ($mount) {
        $self->not_found;
        return;
    }

    # TODO: check auth

    # create UDP socket
    my($name, $alias, $udp_proto) = AnyEvent::Socket::getprotobyname('udp');
    socket my($sock), PF_INET, SOCK_DGRAM, $udp_proto;
    AnyEvent::Util::fh_nonblocking $sock, 1;
    my $dest = sockaddr_in($port, Socket::inet_aton($self->client_address));
    
    $self->client_socket_dest($dest);
    $self->client_socket($sock);

    $self->push_ok;
}

sub stop {
    my ($self) = @_;

    $self->close_socket;

    $self->push_ok;
}

sub setup {
    my ($self) = @_;

    my $mount_path = $self->get_mount_path
        or return $self->bad_request;

    # strip off stream_id for now
    my ($stream_id) = $mount_path =~ s!/streamid=(\d+)!!sgm;
    $self->debug("setup stream id $stream_id");

    my $mount = $self->get_mount($mount_path)
        or return $self->not_found;

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

    # save starting RTP port
    $self->client_rtp_port($client_rtp_start_port);

    $mount->add_client($self);

    $self->push_ok;
}

sub send_packet {
    my ($self, $pkt) = @_;

    return unless $self->client_socket;

    send $self->client_socket, $pkt, 0, $self->client_socket_dest;
}

sub close_socket {
    my ($self) = @_;

    my $mount = $self->get_mount;
    $mount->add_client($self) if $mount;

    my $sock = $self->client_socket or return;
    shutdown $sock, 1;  # done writing
    $self->clear_client_socket;
}

sub DEMOLISH {
    my ($self) = @_;

    $self->close_socket;
}

__PACKAGE__->meta->make_immutable;

