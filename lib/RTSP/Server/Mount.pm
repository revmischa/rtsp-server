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

has 'range' => (
    is => 'rw',
    isa => 'Str',
    clearer => 'clear_range',
);

has 'mounted' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

# map of stream_id -> stream
has '_streams' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
);

sub add_stream {
    my ($self, $stream) = @_;
    $self->_streams->{$stream->index} = $stream;
}

sub remove_stream {
    my ($self, $stream) = @_;
    delete $self->_streams->{$stream->index};
}

sub streams {
    my ($self) = @_;
    return values %{ $self->_streams };
}

sub get_stream {
    my ($self, $stream_id) = @_;
    return $self->_streams->{$stream_id};
}

sub remove_client {
    my ($self, $client) = @_;

    foreach my $stream ($self->streams) {
        $stream->remove_client($client);
    }
}

__PACKAGE__->meta->make_immutable;

