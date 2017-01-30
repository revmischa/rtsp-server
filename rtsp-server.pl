#!/usr/bin/env perl

use strict;
use warnings;
use lib 'lib';

use AnyEvent;
use RTSP::Server;

# you may pass your own options in here or via command-line
my $srv = RTSP::Server->new_with_options(
);
$srv->mounts_callback(sub {
    foreach my $path(keys %{$srv->mounts}){
        print substr($path, 1) . "\n";
    }
    print "\n";
    return;
});

# listen and accept incoming connections
$srv->listen;

# main loop
my $cv = AnyEvent->condvar;

# end if interrupt
$SIG{INT} = sub {
    $cv->send;
};

$cv->recv;
