package RTSP::Server::Session;

use Moose;
use namespace::autoclean;

our $uniq = 1;

has 'session_id' => (
    is => 'rw',
    isa => 'Str',
    lazy => 1,
    builder => 'build_session_id',
);

sub build_session_id {
    my ($self) = @_;

    return $uniq++;
}

__PACKAGE__->meta->make_immutable;
