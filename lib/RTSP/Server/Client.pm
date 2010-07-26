# This class represents a server which listens and accepts client
# requests to stream video

package RTSP::Server::Client;

use Moose;
    with 'RTSP::Server::Listener';

use namespace::autoclean;

has 'connection_class' => (
    is => 'ro',
    isa => 'Str',
    default => 'Client',
);

__PACKAGE__->meta->make_immutable;
