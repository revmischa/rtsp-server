package RTSP::Server::Session;

use Moose;
use namespace::autoclean;

our $uniq = 1;

has 'rtp_start_port' => (
    is => 'rw',
    isa => 'Int',
    required => 1,
);

has 'rtp_end_port' => (
    is => 'rw',
    isa => 'Int',
    lazy => 1,
    builder => 'build_rtp_end_port',
);

has 'session_id' => (
    is => 'rw',
    isa => 'Str',
    lazy => 1,
    builder => 'build_session_id',
);

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

sub build_session_id {
    my ($self) = @_;

    return $uniq++;
}

sub start_rtp_listener {
    my ($self) = @_;
}

__PACKAGE__->meta->make_immutable;
