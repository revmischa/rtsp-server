# This class represents a server which listens and accepts source
# requests to publish a video stream

package RTSP::Server::Source;

use Moose;
    with 'RTSP::Server::Listener';

use namespace::autoclean;

has 'connection_class' => (
    is => 'ro',
    isa => 'Str',
    default => 'Source',
);

__PACKAGE__->meta->make_immutable;
