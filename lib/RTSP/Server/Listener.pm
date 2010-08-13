package RTSP::Server::Listener;

use Moose::Role;
use namespace::autoclean;

use AnyEvent::Handle;
use AnyEvent::Socket;

use RTSP::Server::Source::Connection;
use RTSP::Server::Client::Connection;
use Socket;
use Socket6;

has 'listen_address' => (
    is => 'rw',
    isa => 'Str',
    required => 1,
);

has 'listen_port' => (
    is => 'rw',
    isa => 'Int',
    required => 1,
);

has 'listener' => (
    is => 'rw',
);

has 'connection_class' => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has 'next_connection_id' => (
    is => 'rw',
    isa => 'Int',
    default => 1,
);

# map of id => $connection
has 'connections' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
    lazy => 1,
);

has 'server' => (
    is => 'ro',
    isa => 'RTSP::Server',
    required => 1,
    handles => [qw/ mounts trace debug info warn error max_clients /],
);

sub connection_count {
    my ($self) = @_;

    # TODO: don't double-count connections with the same IP or
    # sessionid to prevent DoS
    return scalar(keys %{ $self->{connections} });
}

sub listen {
    my ($self) = @_;

    my $bind_ip = $self->listen_address;
    my $bind_port = $self->listen_port;
    my $conn_class = $self->connection_class;

    my $listener = tcp_server $bind_ip, $bind_port, sub {
        my ($fh, $rhost, $rport) = @_;
        
        $self->info("$conn_class connection from $rhost:$rport");

        my $addr_family = sockaddr_family(getsockname($fh));
        my ($local_port, $local_addr);
        if ($addr_family == AF_INET) {
            ($local_port, $local_addr) = sockaddr_in(getsockname($fh));
            $local_addr = inet_ntoa($local_addr);
        } elsif ($addr_family == AF_INET6) {
            ($local_port, $local_addr) = sockaddr_in6(getsockname($fh));
            $local_addr = inet_ntop(AF_INET6, $local_addr);
        }

        # create object to track client
        my $conn = "RTSP::Server::${conn_class}::Connection"->new(
            id => $self->next_connection_id,
            client_address => $rhost,
            client_port => $rport,
            local_address => $local_addr,
            addr_family => $addr_family,
            server => $self->server,
        );

        $self->next_connection_id($self->next_connection_id + 1);

        my $handle;
        my $cleanup = sub {
            delete $self->connections->{$conn->id};
            $handle->destroy;
            undef $handle;
        };

        $handle = new AnyEvent::Handle
            fh => $fh,
            on_eof => sub {
                $self->debug("Got EOF on listener");
                $cleanup->();
            },
            on_error => sub {
                my (undef, $fatal, $msg) = @_;

                $self->error("Got " . ($fatal ? 'fatal ' : '') . 
                             "error on $conn_class listener socket: $msg");
                $cleanup->();
            },
            on_read => sub {
                $handle->push_read(
                    line => sub {
                        my (undef, $line, $eol) = @_;

                        $self->trace("$conn_class listener: >> $line");

                        # parse line of request
                        if (! $conn->current_method) {
                            # expecting method, URI, RTSP/1.0
                            my ($method, $uri, $version) = $line =~ m/
                                ^\s*(\w+)\s+         # method
                                (?:(.+)\s+)?         # optional uri
                                RTSP\/([\d\.]+)\s*$  # version
                            /ix;

                            unless ($method && $version) {
                                $self->error("Unable to parse request '$line'");
                                $conn->push_response(400, "Bad Request");
                                return;
                            }

                            $self->debug("Got method $method");

                            $conn->current_method($method);
                            $conn->req_uri($uri) if $uri;
                            $conn->expecting_header(1);
                        } elsif ($conn->expecting_header) {
                            # expecting header
                            if (! $line) {
                                # end of headers
                                $self->trace("End of headers");

                                $conn->expecting_header(0);

                                # did we get content-length? if so, we are expecting the body
                                my $length = $conn->req_content_length;
                                if ($length) {
                                    $handle->push_read(chunk => $length, sub {
                                        my (undef, $data) = @_;

                                        $self->trace("Finished reading body, length=$length");
                                        $conn->body($data);

                                        $conn->request_finished;
                                    });
                                } else {
                                    $conn->request_finished;
                                }
                            } else {
                                # we got a header
                                my ($header, $value) = $line =~ m/\s*([-\w]+)\s*:\s+(.*)$/;
                                $conn->add_req_header($header, $value);
                            }
                        } else {
                            # not expecting header, not expecting method. should not get here.
                            $self->error("Unable to parse line: $line");
                        }
                    },
                );
            };

        $conn->h($handle);

        # save connection object
        $self->connections->{$conn->id} = $conn;
    } or die $!;
    
    $self->listener($listener);
}

1;
