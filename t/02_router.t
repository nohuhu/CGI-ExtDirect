use strict;
use warnings;

use Test::More tests => 25;

use Data::Dumper;

use CGI::Test ();       # No need to import ok() from CGI::Test
use CGI::Test::Input ();
use CGI::Test::Input::URL ();
use CGI::Test::Input::Multipart ();

BEGIN { use_ok 'CGI::ExtDirect'; }

my $dfile = 't/data/extdirect/route';
my $tests = eval do { local $/; open my $fh, '<', $dfile; <$fh> } ## no critic
    or die "Can't eval $dfile: '$@'";

# Testing API
my $ct = CGI::Test->new(
    -base_url => 'http://localhost/cgi-bin',
    -cgi_dir  => 't/cgi-bin',
);

BAIL_OUT "Can't create CGI::Test object" unless $ct;

for my $test ( @$tests ) {
    my $name            = $test->{name};
    my $url             = $test->{cgi_url};
    my $method          = $test->{method};
    my $input_content   = $test->{input_content};
    my $http_status_exp = $test->{http_status};
    my $content_regex   = $test->{content_type};
    my $expected_output = $test->{expected_content};

    my $page = $ct->$method($url, $input_content);

    if ( ok $page, "$name not empty" ) {
        my $content_type = $page->content_type();
        my $http_status  = $page->is_ok() ? 200 : $page->error_code();

        like $content_type, $content_regex,   "$name content type";
        is   $http_status,  $http_status_exp, "$name HTTP status";

        my $http_output  = $page->raw_content();
        $http_output     =~ s/\s//g;
        $expected_output =~ s/\s//g;

        is $http_output, $expected_output, "$name content"
            or do {
                local $Data::Dumper::Indent = 1;
                BAIL_OUT( Data::Dumper->Dump( [ $page ], [ 'page' ] ) );
            };

        $page->delete();
    };
};

exit 0;

sub raw_post {
    my ($url, $input) = @_;

    use bytes;
    my $cgi_input = CGI::Test::Input::URL->new();
    $cgi_input->add_field('POSTDATA', $input);

    return $cgi_input;
}

sub form_post {
    my ($url, %fields) = @_;

    use bytes;
    my $cgi_input = CGI::Test::Input::URL->new();
    for my $field ( keys %fields ) {
        my $value = $fields{ $field };
        $cgi_input->add_field($field, $value);
    };

    return $cgi_input;
}

sub form_upload {
    my ($url, $files, %fields) = @_;

    my $cgi_input = CGI::Test::Input::Multipart->new();

    for my $field ( keys %fields ) {
        my $value = $fields{ $field };
        $cgi_input->add_field($field, $value);
    };

    for my $file ( @$files ) {
        $cgi_input->add_file_now("upload", "t/data/cgi-data/$file");
    };

    return $cgi_input;
}
