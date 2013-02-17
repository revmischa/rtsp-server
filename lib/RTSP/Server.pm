package RTSP::Server;

use Moose;
    with 'MooseX::Getopt';

use namespace::autoclean;

use RTSP::Server::Logger;
use RTSP::Server::Source;
use RTSP::Server::Client;

our $VERSION = '0.06';
our $RTP_START_PORT = 20_000;

## configuration attributes

has 'client_listen_port' => (
    is => 'rw',
    isa => 'Int',
    default => '554',
    cmd_flag => 'clientport',
    cmd_aliases => 'c',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

has 'source_listen_port' => (
    is => 'rw',
    isa => 'Int',
    default => '5545',
    cmd_flag => 'serverport',
    cmd_aliases => 's',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
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
    cmd_flag => 'loglevel',
    cmd_aliases => 'l',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

has 'max_clients' => (
    is => 'rw',
    isa => 'Int',
    default => 100,
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
    traits => [ 'NoGetopt' ],
);

has 'client_server' => (
    is => 'rw',
    clearer => 'close_client_server',
    traits => [ 'NoGetopt' ],
);

has 'logger' => (
    is => 'rw',
    isa => 'RTSP::Server::Logger',
    handles => [qw/ trace debug info warn error /],
    lazy => 1,
    builder => 'build_logger',
    traits => [ 'NoGetopt' ],
);

# map of uri => Mount
has 'mounts' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
    lazy => 1,
    traits => [ 'NoGetopt' ],
);

sub client_count {
    my ($self) = @_;

    return $self->client_server->connection_count;
}

sub client_stopped {
    my ($self, $client) = @_;
    $self->client_count($self->client_count + 1);
}

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

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

RTSP::Server - Lightweight RTSP/RTP server. Like icecast, for
audio/video streams.

=head1 SYNOPSIS

  use AnyEvent;
  use RTSP::Server;

  # defaults:
  my $srv = new RTSP::Server(
      log_level             => 2,   # 0 = no output, 5 = most verbose
      max_clients           => 100,
      client_listen_port    => 554,
      source_listen_port    => 5545,
      rtp_start_port        => 20000,
      client_listen_address => '0.0.0.0',
      source_listen_address => '0.0.0.0',
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

This server is designed to enable to rebroadcasting of RTP media
streams to clients, controlled by RTSP. Please see README for more
information.

=head1 USAGE

After starting the server, stream sources may send an ANNOUNCE for a
desired mountpoint, followed by a RECORD request to begin streaming.
Clients can then connect on the client port at the same mountpoint and
send a PLAY request to receive the RTP data streamed from the source.

=head1 BUNDLED APPLICATIONS

Includes rtsp-server.pl, which basically contains the synopsis.

=head2 COMING SOON

Priv dropping, authentication, client encoder, stats, tests

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
