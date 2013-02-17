package RTSP::Server::Connection;

use Moose::Role;
use namespace::autoclean;

use RTSP::Server::Session;
use RTSP::Server::Mount;

use Carp qw/croak/;
use URI;

has 'id' => (
    is => 'ro',
    isa => 'Int',
    required => 1,
);

has 'client_address' => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has 'client_port' => (
    is => 'ro',
    isa => 'Int',
    required => 1,
);

has 'local_address' => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has 'addr_family' => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has 'handle' => (
    is => 'rw',
    accessor => 'h',
);

has 'current_method' => (
    is => 'rw',
    isa => 'Str',
    clearer => 'clear_current_method',
);

has 'req_uri' => (
    is => 'rw',
    isa => 'Str',
    clearer => 'clear_req_uri',
);

has 'expecting_header' => (
    is => 'rw',
    isa => 'Bool',
);

has 'body' => (
    is => 'rw',
    isa => 'Str',
    clearer => 'clear_body',
);

# map of header => \@values
has 'req_headers' => (
    is => 'rw',
    isa => 'HashRef',
    clearer => 'clear_req_headers',
    lazy => 1,
    default => sub { {} },
);

# map of header => \@values
has 'resp_headers' => (
    is => 'rw',
    isa => 'HashRef',
    clearer => 'clear_resp_headers',
    lazy => 1,
    default => sub { {} },
);

has 'session' => (
    is => 'rw',
    isa => 'RTSP::Server::Session',
    handles => [qw/ session_id /],
    lazy => 1,
    builder => 'build_session',
    clearer => 'clear_session',
);

has 'server' => (
    is => 'ro',
    isa => 'RTSP::Server',
    required => 1,
    predicate => 'server_exists',
    handles => [qw/ next_rtp_start_port mounts trace debug info warn error /],
);

# should return a list of supported methods
sub public_options {
    return qw/OPTIONS DESCRIBE TEARDOWN/;
}

sub private_options {
    return qw//;
}

sub teardown {
    my ($self) = @_;

    $self->clear_session;
}

sub describe {
    my ($self) = @_;

    my $mount = $self->get_mount
        or return $self->not_found;

    $self->add_resp_header('Content-Type', 'application/sdp');

    $self->push_ok($mount->sdp);
}

sub options {
    my ($self) = @_;

    my @pub_methods = $self->public_options;
    my @priv_methods = $self->private_options;

    $self->add_resp_header('Public',  join(', ', @pub_methods));
    $self->add_resp_header('Private', join(', ', @priv_methods))
        if @priv_methods;

    $self->push_ok;
}

sub bad_request {
    my ($self) = @_;
    $self->push_response(400, "Bad Request");
}

sub not_found {
    my ($self) = @_;

    $self->info("Returning 404 for " . $self->req_uri);

    $self->push_response(404, "Not Found");
}

sub internal_server_error {
    my ($self) = @_;
    $self->push_response(500, "Internal Server Error");
}

sub push_ok {
    my ($self, $body) = @_;
    $self->push_response(200, 'OK', $body);
}

sub build_session {
    my ($self) = @_;

    my $sess = RTSP::Server::Session->new(
    );

    return $sess;
}

sub request_finished {
    my ($self) = @_;

    my $method = $self->current_method;
    unless ($method) {
        $self->error("Finished parsing request but did not find method");
        return;
    }

    $self->handle_request;
}

sub handle_request {
    my ($self) = @_;

    unless ($self->current_method) {
        croak "handle_request called without current_method set";
    }

    my $method = lc $self->current_method;

    # TODO: check auth
    my @allowed_methods = ($self->public_options, $self->private_options);
    if (grep { lc $_ eq $method } @allowed_methods) {
        my $ok = eval {
            $self->$method;
            1;
        };

        if (! $ok || $@) {
            $self->error("Error handling " . uc($method) . ": " .
                         ($@ || 'unknown error'));
        }
    } else {
        $self->push_response(405, 'Method Not Allowed');
    }

    $self->reset;
}

sub add_req_header {
    my ($self, $hdr, $val) = @_;

    $self->req_headers->{$hdr} ||= [];
    my $vals = $self->req_headers->{$hdr};
    push @$vals, $val;

    return $val;
}

sub add_resp_header {
    my ($self, $hdr, $val) = @_;

    $self->resp_headers->{$hdr} ||= [];
    my $vals = $self->resp_headers->{$hdr};
    push @$vals, $val;

    return $val;
}

# get a single header value. warns if multiple values are found
sub get_req_header {
    my ($self, $hdr) = @_;

    my $vals = $self->req_headers->{$hdr} or return;
    if (@$vals > 1) {
        $self->warn("Found multiple values for request header '$hdr' but expected only one");
    }

    return $vals->[0];
}

# same as above
sub get_resp_header {
    my ($self, $hdr) = @_;

    my $vals = $self->resp_headers->{$hdr} or return;
    if (@$vals > 1) {
        $self->warn("Found multiple values for response header '$hdr' but expected only one");
    }

    return $vals->[0];
}

sub push_response {
    my ($self, $code, $msg, $body) = @_;

    return unless $self->h;
    $self->push_resp_line("RTSP/1.0 $code $msg");

    # push headers
    foreach my $hdr (keys %{ $self->resp_headers }) {
        foreach my $val (@{ $self->resp_headers->{$hdr} }) {
            $self->push_resp_line("$hdr: $val");
        }
    }

    # add content-length header if there's a body to return
    $self->push_resp_line("Content-Length: " . length($body))
        if $body;

    # add cseq, if available
    my $cseq = $self->req_cseq;
    $self->push_resp_line("CSeq: $cseq") if $cseq;

    # add session id, if available
    if ($self->session) {
        my $session_id = $self->session->session_id;
        $self->push_resp_line("Session: $session_id");
    }

    # end of headers
    $self->h->push_write("\r\n");

    # body?
    $self->h->push_write($body) if $body;

    $self->info("Returning error $code: $msg")
        if $code !~ /2\d\d/;
}

sub push_resp_line {
    my ($self, $line) = @_;

    $self->trace(" << $line");
    $self->h->push_write("$line\r\n");
}

sub req_cseq {
    my ($self) = @_;

    return $self->get_req_header('cseq') ||
        $self->get_req_header('Cseq') ||
        $self->get_req_header('CSeq');
}

sub req_content_length {
    my ($self) = @_;

    return $self->get_req_header('content-length') ||
        $self->get_req_header('Content-length') ||
        $self->get_req_header('Content-Length');
}

# parse a uri, find the path
sub get_mount_path {
    my ($self, $uri) = @_;

    $uri ||= $self->req_uri or return;
    my $u = new URI($uri) or return;

    my $path = $u->path or return;

    return $path;
}

# get a stream
sub get_mount {
    my ($self, $path) = @_;

    $path ||= $self->get_mount_path or return;

    my ($stream_id) = $path =~ m!/streamid=(\d+)!sm;
    $path =~ s!/streamid=(\d+)!!sm;

    my $mnt = $self->mounts->{$path};
    return wantarray ? ($mnt, $stream_id) : $mnt;
}

# returns new mount point
sub mount {
    my ($self, %opts) = @_;

    # check args
    my ($path, $sdp);
    {
        $path = delete $opts{path}
        or croak "Connection->mount() called with no path";

        $sdp = delete $opts{sdp}
        or croak "Connection->mount() called with no SDP info";

        croak 'Unknown options: ' . join(', ', keys %opts)
            if keys %opts;
    }

    # unmount existing mountpoint if it exists
    $path ||= $self->get_mount_path or return;
    $self->unmount($path) if $self->get_mount($path);

    # create mount point
    my $mount = new RTSP::Server::Mount(
        path => $path,
        sdp  => $sdp,
    );

    $self->mounts->{$path} = $mount;

    $self->info("Mounted $path");

    return $mount;
}

# delete a stream
sub unmount {
    my ($self, $path) = @_;

    $path ||= $self->get_mount_path or return;
    delete $self->mounts->{$path};

    $self->info("Unmounting $path");
}

sub reset {
    my ($self) = @_;

    $self->clear_req_headers;
    $self->clear_resp_headers;

    $self->clear_req_uri;
    $self->clear_current_method;
    $self->clear_body;
    $self->expecting_header(0);
}

sub DEMOLISH {
    my ($self) = @_;

    $self->server->housekeeping if $self->server_exists;
}

1;
