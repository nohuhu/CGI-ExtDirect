use 5.006000;
use ExtUtils::MakeMaker;

# First prepare test and example cgi scripts
my $perl = $^X;

my $we_are_unixy = $^O !~ /DOS|Win32|VMS/;

my @dirs = (
    [ 't/data/examples/cgi-bin', 'examples/htdocs/cgi-bin', ],
    [ 't/data/examples',         'examples',                ],
);

while ( @dirs ) {
    my ($src_dir, $dst_dir) = @{ shift @dirs };

    system "mkdir -p $dst_dir" if $we_are_unixy;

    my @files = glob "$src_dir/*.src";

    for my $file ( @files ) {
        local $/;

        open my $fh, '<', $file or die "Can't open $file for reading: $!";
        my $script = <$fh>;
        close $fh;

        die "Can't find Perl placeholder in script $file!"
            unless $script =~ s/\A#!PUT_PERL_HERE/#!$perl/ms;

        my ($fname)   = $file =~ ( m{ \A .* [\/] (.*?) \.src \z }ixms );
        my $dest_name = $fname eq 'p5httpd' ? "$dst_dir/$fname.pl"
                      :                       "$dst_dir/$fname.cgi"
                      ;

        open $fh, '>', $dest_name or
            die "Can't open $dest_name for writing: $!";
        print $fh $script;
        close $fh;

        system "chmod +x $dest_name" if $we_are_unixy;
    };
};

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

# Finally, write Makefile
WriteMakefile(
    NAME              => 'CGI::ExtDirect',
    VERSION_FROM      => 'lib/CGI/ExtDirect.pm', # finds $VERSION
    ($ExtUtils::MakeMaker::VERSION >= 6.55
        ? ( BUILD_REQUIRES    => {
            'Test::More'     => 0,
            'CGI::Test'      => '0.31',
          },
          PREREQ_PM         => {
            'RPC::ExtDirect' => '3.00',
          },
        )
        : ( PREREQ_PM => {
                'Test::More'     => 0,
                'CGI::Test'      => '0.31',
                'RPC::ExtDirect' => '3.00',
            },
        )
    ),
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT => 'RPC::ExtDirect gateway for CGI', 
       AUTHOR   => 'Alex Tokarev <tokarev@cpan.org>',
       LICENSE  => 'perl') : ()),

    ($ExtUtils::MakeMaker::VERSION >= 6.46
        ? ( META_MERGE => {
            resources   => {
                bugtracker  => 'http://github.com/nohuhu/CGI-ExtDirect/issues',
                repository  => 'http://github.com/nohuhu/CGI-ExtDirect',
            },
           },
        )
        : ()
    ),

    clean => { FILES => 'examples/p5httpd.pl '.
                        'examples/htdocs/cgi-bin/*.cgi '.
                        't/cgi-bin/*.cgi' },
);

