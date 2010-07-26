package RTSP::Server::RTPListener;

use Moose;
use namespace::autoclean;

use AnyEvent::Util;
use Socket;

has 'mount' => (
    is => 'ro',
    isa => 'RTSP::Server::Mount',
    required => 1,
);

has 'stream' => (
    is => 'ro',
    isa => 'RTSP::Server::Mount::Stream',
    required => 1,
);

has 'host' => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has 'port' => (
    is => 'ro',
    isa => 'Int',
    required => 1,
);

has 'read_size' => (
    is => 'rw',
    isa => 'Int',
    default => 1420,
);

has 'watcher' => (
    is => 'rw',
);

has 'socket' => (
    is => 'rw',
);

sub listen {
    my ($self) = @_;

    # create UDP listener socket
    my($name, $alias, $udp_proto) = AnyEvent::Socket::getprotobyname('udp');
    socket my($sock), PF_INET, SOCK_DGRAM, $udp_proto;
    AnyEvent::Util::fh_nonblocking $sock, 1;

    unless (bind $sock, sockaddr_in($self->port, Socket::inet_aton($self->host))) {
        warn("Error binding UDP listener to port " . $self->port . ": $!");
        return;
    }

    $self->socket($sock);

    my $buf;
    my $read_size = $self->read_size;

    my $w; $w = AnyEvent->io(
        fh => $sock,
        poll => 'r', cb => sub {
            my $sender_addr = recv $sock, $buf, $read_size, 0;

            # TODO: compare $sender_addr to expected addr

            if (! defined $sender_addr) {
                # error
                $self->error("Error receiving RTP data");
                undef $w;

                return;
            }

            next unless $buf;

            $self->stream->broadcast($buf);
        }
    );

    $self->watcher($w);

    # TODO: send UDP packet every 30 seconds to keep stateful UDP
    # firewalls open

    return 1;
}

sub DEMOLISH {
    my ($self) = @_;

    if ($self->socket) {
        shutdown $self->socket, 2;
    }

    if ($self->child) {
        $self->child->kill(2); # SIGINT
    }
}

__PACKAGE__->meta->make_immutable;
