package RTSP::Server::Mount::Stream;

use Moose;
use namespace::autoclean;

has 'index' => (
    is => 'ro',
    isa => 'Int',
    required => 1,
);

has 'client_rtp_port' => (
    is => 'rw',
    isa => 'Int',
);

has 'rtp_start_port' => (
    is => 'ro',
    isa => 'Int',
);

has 'rtp_end_port' => (
    is => 'rw',
    isa => 'Int',
    lazy => 1,
    builder => 'build_rtp_end_port',
);

# map of session_id -> client connection
has '_clients' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
);

sub clients {
    my ($self) = @_;
    return values %{ $self->_clients };
}

sub add_client {
    my ($self, $client) = @_;
    $self->_clients->{$client->session_id} = $client;
}

sub remove_client {
    my ($self, $client) = @_;
    delete $self->_clients->{$client->session_id};
}

# broadcast a packet to all clients
sub broadcast {
    my ($self, $pkt) = @_;

    foreach my $client ($self->clients) {
        $client->send_packet($self->index, $pkt);
    }
}

sub build_rtp_end_port {
    my ($self) = @_;
    return $self->rtp_start_port + 1;
}

sub rtp_port_range {
    my ($self) = @_;

    my (@rtp_listen_ports) = $self->get_rtp_listen_ports;
    my $port_range = $rtp_listen_ports[0] . '-' .
        $rtp_listen_ports[scalar @rtp_listen_ports - 1];

    return $port_range;
}

sub get_rtp_listen_ports {
    my ($self) = @_;

    return ( $self->rtp_start_port .. $self->rtp_end_port );
}

__PACKAGE__->meta->make_immutable;
