use 5.006000;
use ExtUtils::MakeMaker;

# Add the `devtest` target to run regression and POD tests in one go
sub MY::postamble {
    return <<'END';
devtest :
	REGRESSION_TESTS=1 POD_TESTS=1 $(MAKE) test

END
}

# Override `disttest` so it would behave as `devtest`
sub MY::dist_test {
    return <<'END';
disttest : distdir
	cd $(DISTVNAME) && $(ABSPERLRUN) Makefile.PL
	cd $(DISTVNAME) && $(MAKE) $(PASTHRU)
	cd $(DISTVNAME) && $(MAKE) devtest $(PASTHRU)

END
}

my $MM_VERSION = $ExtUtils::MakeMaker::VERSION;

WriteMakefile(
    NAME              => 'CGI::ExtDirect',
    VERSION_FROM      => 'lib/CGI/ExtDirect.pm',
    ($MM_VERSION >= 6.55
        ? ( BUILD_REQUIRES    => {
            'Test::More'     => '0.82',
            'CGI::Test'      => '0.32',
          },
          PREREQ_PM         => {
            # 5.20 warns that CGI is going to be removed from
            # perl distro in 5.22, so we require it here
            'CGI'            => 0,
            'RPC::ExtDirect' => '3.01',
          },
        )
        : ( PREREQ_PM => {
                'Test::More'     => '0.82', # for explain()
                'CGI::Test'      => '0.32',
                'CGI'            => 0,
                'RPC::ExtDirect' => '3.01',
            },
        )
    ),

    ABSTRACT => 'RPC::ExtDirect gateway for CGI', 
    AUTHOR   => 'Alex Tokarev <tokarev@cpan.org>',
    LICENSE  => 'perl',

    ($MM_VERSION >= 6.48
        ? ( MIN_PERL_VERSION => 5.006000 )
        : (),
    ),

    ($MM_VERSION >= 6.46
        ? ( META_MERGE => {
            resources   => {
                bugtracker  => 'http://github.com/nohuhu/CGI-ExtDirect/issues',
                repository  => 'http://github.com/nohuhu/CGI-ExtDirect',
            },
           },
        )
        : ()
    ),
);

