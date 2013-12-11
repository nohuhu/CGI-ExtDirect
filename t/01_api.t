use strict;
use warnings;
no  warnings 'uninitialized';

use Test::More tests => 13;

use RPC::ExtDirect::Test::Util;

use CGI::Test ();       # No need to import ok() from CGI::Test
use CGI::Test::Input ();
use CGI::Test::Input::URL ();
use CGI::Test::Input::Multipart ();

BEGIN { use_ok 'CGI::ExtDirect'; }

my $dfile = 't/data/extdirect/api';
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

        my $http_output   = $page->raw_content();
        my $actual_data   = deparse_api($http_output);
        my $expected_data = deparse_api($expected_output);

        is_deeply $actual_data, $expected_data, "$name content"
            or diag explain $actual_data;

        $page->delete();
    };
};

exit 0;

sub raw_post {
    my $input = shift;

    use bytes;
    my $cgi_input        = CGI::Test::Input::URL->new();
    $cgi_input->add_field('POSTDATA', $input);

    return $cgi_input;
};
