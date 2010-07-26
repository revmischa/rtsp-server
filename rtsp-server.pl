#!/usr/bin/env perl

use strict;
use warnings;
use lib 'lib';

use AnyEvent;
use RTSP::Server;

my $srv = RTSP::Server->new_with_options(
    max_clients => 10,
    log_level => 4,
);

# listen and accept incoming connections
$srv->listen;

# main loop
my $cv = AnyEvent->condvar;

# end if interrupt
$SIG{INT} = sub {
    $cv->send;
};

$cv->recv;
