package RTSP::Server::Mount;

use Moose;
use namespace::autoclean;

has 'path' => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has 'sdp' => (
    is => 'rw',
    required => 1,
);

has 'mounted' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

# map of session_id -> client connection
has 'clients' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
);

sub add_client {
    my ($self, $client) = @_;

    $self->clients->{$client->session_id} = $client;
}

sub remove_client {
    my ($self, $client) = @_;

    delete $self->clients->{$client->session_id};
}

# broadcast a video packet to all clients
sub broadcast {
    my ($self, $pkt) = @_;

    foreach my $client (values %{ $self->clients }) {
        $client->send_packet($pkt);
    }
}

__PACKAGE__->meta->make_immutable;

