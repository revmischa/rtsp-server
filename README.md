RTSP-Server
===========
This module is designed to accept a number of sources to connect and
transmit audio and video streams.
Clients can connect and send RTSP commands to receive RTP data.

This was designed to make rebroadcasting audio and video data over a
network simple.

## INSTALLATION
To install this module type the following:
```
   perl Makefile.PL
   make
   make test
   make install
```
### LINUX

To install debian jessie dependences:
```
   sudo apt-get install libmoose-perl liburi-perl libmoosex-getopt-perl libsocket6-perl libanyevent-perl
   sudo cpan AnyEvent::MPRPC::Client

Clone from git
   git clone https://github.com/revmischa/rtsp-server

Then make, test and install
   perl Makefile.PL
   make
   make test
   make install

```
### MAC OS X

```shell
cpanm Moose
cpanm Socket6
cpanm MooseX::Getopt
cpanm URI
cpanm AnyEvent

sudo cpan AnyEvent::MPRPC::Client

Clone from git
   git clone https://github.com/revmischa/rtsp-server

Then make, test and install
   perl Makefile.PL
   make
   make test
   make install
```

#### Use ffmpeg to stream your local camera

You can view available cameras with: `ffmpeg -f avfoundation -list_devices true -i ""`

If you are using a Macbook Pro, then use the below commands:

```shell
brew install ffmpeg jack

ffmpeg -re -f avfoundation -video_size 320x240 -framerate 30 -pixel_format bgr0
-i "FaceTime HD Camera" -f rtsp -muxdelay 0.1 rtsp://127.0.0.1:5545/a_video_stream
```

## RUNNING

Simply fire up the included rtsp-server.pl application and it will
listen for clients on port 554 (standard RTSP port), and source
streams on port 5545.

To begin sending video, you can use any client which supports the
ANNOUNCE and RECORD RTSP methods, such as [FFmpeg](https://www.ffmpeg.org/ffmpeg-protocols.html#rtsp):

`ffmpeg -re -i /input.avi -f rtsp -muxdelay 0.1 rtsp://12.34.56.78:5545/abc`

You should then be able to play that stream with any decent media
player. Just point it at rtsp://12.34.56.78/abc

If you don't want to run it as root, you may specify non-priviliged
ports with `--clientport/-c` and `--sourceport/-s`

## DEPENDENCIES

This module requires these other modules and libraries:

  Moose, AnyEvent::Socket, AnyEvent::Handle

## COPYRIGHT AND LICENCE

ABRMS

## Maintainership

Want to take over maintaining this project? Feel free. 
