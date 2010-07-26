package RTSP::Server;

#use 5.010000;
use Moose;
use namespace::autoclean;

use RTSP::Server::Logger;
use RTSP::Server::Source;
use RTSP::Server::Client;

our $VERSION = '0.01';
our $RTP_START_PORT = 20_000;

## configuration attributes

has 'client_listen_port' => (
    is => 'rw',
    isa => 'Int',
    default => '5454',
);

has 'source_listen_port' => (
    is => 'rw',
    isa => 'Int',
    default => '5455',
);

has 'client_listen_address' => (
    is => 'rw',
    isa => 'Str',
    default => '0.0.0.0',
);

has 'source_listen_address' => (
    is => 'rw',
    isa => 'Str',
    default => '0.0.0.0',
);

has 'log_level' => (
    is => 'rw',
    isa => 'Int',
    default => 2,
);

## internal attributes

has 'rtp_start_port' => (
    is => 'rw',
    isa => 'Int',
    default => $RTP_START_PORT,
);

has 'source_server' => (
    is => 'rw',
    clearer => 'close_source_server',
);

has 'client_server' => (
    is => 'rw',
    clearer => 'close_client_server',
);

has 'logger' => (
    is => 'rw',
    isa => 'RTSP::Server::Logger',
    handles => [qw/ trace debug info warn error /],
    lazy => 1,
    builder => 'build_logger',
);

# map of uri => Mount
has 'mounts' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
    lazy => 1,
);

sub next_rtp_start_port {
    my ($self) = @_;

    my $port = $self->rtp_start_port;
    $self->rtp_start_port($port + 2);

    return $port;
}

# call from time to time to keep things tidy
sub housekeeping {
    my ($self) = @_;

    # if we have no more mount points, it's safe to reset the rtp
    # start ports
    unless (keys %{ $self->mounts }) {
        $self->rtp_start_port($RTP_START_PORT);
    }
}

# call this to start the server
sub listen {
    my ($self) = @_;

    print "Starting RTSP server, log level = " . $self->log_level . "\n";

    my $source_server = $self->start_source_server;
    my $client_server = $self->start_client_server;
}

sub start_client_server {
    my ($self) = @_;

    $self->close_client_server;

    my $bind_ip = $self->client_listen_address;
    my $bind_port = $self->client_listen_port;

    my $server = RTSP::Server::Client->new(
        listen_address => $bind_ip,
        listen_port => $bind_port,
        server => $self,
    );

    $server->listen;

    $self->client_server($server);
    $self->info("Client server started");
    
    return $server;
}

sub start_source_server {
    my ($self) = @_;

    $self->close_source_server;

    my $bind_ip = $self->source_listen_address;
    my $bind_port = $self->source_listen_port;

    my $server = RTSP::Server::Source->new(
        listen_address => $bind_ip,
        listen_port => $bind_port,
        server => $self,
    );

    $server->listen;

    $self->source_server($server);
    $self->info("Source server started");
    
    return $server;
}

sub build_logger {
    my ($self) = @_;

    return RTSP::Server::Logger->new(
        log_level => $self->log_level
    );
}

1;

__END__

=head1 NAME

RTSP::Server - Lightweight RTSP/RTP server. Like icecast, for video.

=head1 SYNOPSIS

  use AnyEvent;
  use RTSP::Server;

  my $srv = new RTSP::Server(
      mount_points => [qw/ stream1.rtsp stream2.rtsp /],
      max_clients => 10,
  );

  # listen and accept incoming connections asynchronously
  # (returns immediately)
  $srv->listen;

  # main loop
  my $cv = AnyEvent->condvar;
  # ...
  $cv->recv;

  undef $srv;  # when the server goes out of scope, all sockets will
               # be cleaned up

=head1 DESCRIPTION

This server is designed to enable to rebroadcasting of RTSP/RTP
streams to clients.

=head2 EXPORT

None by default.

=head1 TODO

Authentication, automated tests.

=head1 SEE ALSO

L<RTSP::Proxy>, L<RTSP::Client>, L<AnyEvent::Socket>

=head1 AUTHOR

Mischa Spiegelmock, E<lt>revmischa@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Mischa Spiegelmock

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.


=cut
