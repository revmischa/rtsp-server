use 5.010000;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'RTSP::Server',
    VERSION_FROM      => 'lib/RTSP/Server.pm',
    PREREQ_PM         => {
        'Moose' => 0,
        'namespace::autoclean' => 0,
        'AnyEvent::Handle' => 0,
        'AnyEvent::Socket' => 0,
        'AnyEvent::Util' => 0,
        'Socket' => 0,
        'URI' => 0,
        'MooseX::Getopt' => 0,
    },

    META_ADD => { resources => { repository => 'git://github.com/revmischa/rtsp-server.git' } },

    ($] >= 5.005 ?
      (ABSTRACT_FROM  => 'lib/RTSP/Server.pm',
       AUTHOR         => 'Mischa Spiegelmock <revmischa@cpan.org>') : ()),
);
