use strict;
use warnings;
no  warnings 'uninitialized';

# This test is CGI::ExtDirect specific, hence it is not unified with the rest
# of the framework

use Test::More tests => 54;

use lib 't/lib';
use RPC::ExtDirect::Test::Util::CGI qw/ raw_post form_post form_upload /;

use CGI::ExtDirect;

my $tests = eval do { local $/; <DATA>; }       ## no critic
    or die "Can't eval DATA: '$@'";

# Testing API
my $ct = CGI::Test->new(
    -base_url => 'http://localhost/cgi-bin',
    -cgi_dir  => 't/cgi-bin',
);

BAIL_OUT "Can't create CGI::Test object" unless $ct;

my @run_only = @ARGV;

TEST:
for my $test ( @$tests ) {
    my $name             = $test->{name};
    my $cgi_url          = $test->{url};
    my $method           = $test->{method};
    my $input_content    = $test->{input_content};
    my $http_status_exp  = $test->{http_status};
    my $expected_headers = $test->{http_headers};

    next TEST if @run_only && !grep { lc $name eq lc $_ } @run_only;

    my $url  = $ct->base_uri . $cgi_url;
    my $page = $ct->$method($url, $input_content);

    if ( ok $page, "$name not empty" ) {
        my $http_status  = $page->is_ok() ? 200 : $page->error_code();
        is   $http_status,  $http_status_exp, "$name HTTP status";

        my $http_headers = $ct->http_headers;

        for my $exp_header ( keys %$expected_headers ) {
            ok exists $http_headers->{ $exp_header },
                "$name $exp_header exists";
            is $http_headers->{ $exp_header },
               $expected_headers->{ $exp_header }, "$name $exp_header value"
                    or diag explain $page;
        };

        $page->delete();
    };
};

__DATA__
[
    { name => 'One parameter', method => 'POST', http_status => 200,
      url => '/header1', input_content => undef,
      http_headers => {
        'Status'            => '200 OK',
        'Content-Type'      => 'application/json; charset=utf-8',
        'Content-Length'    => '44',
      },
    },
    { name => 'Two parameters', method => 'POST', http_status => 200,
      url => '/header2', input_content => undef,
      http_headers => {
        'Status'            => '200 OK',
        'Content-Type'      => 'application/json; charset=utf-8',
        'Content-Length'    => '44',
      },
    },
    { name => 'Charset override', method => 'POST', http_status => 200,
      url => '/header3', input_content => undef,
      http_headers => {
        'Status'            => '200 OK',
        'Content-Type'      => 'application/json; charset=iso-8859-1',
        'Content-Length'    => '44',
      },
    },
    { name => 'Event provider cookie headers', method => 'POST',
      http_status => 200,
      url => '/header4', input_content => undef,
      http_headers => {
        'Status'            => '200 OK',
        'Content-Type'      => 'application/json; charset=iso-8859-1',
        'Content-Length'    => '44',
        'Set-Cookie'        => 'sessionID=xyzzy; domain=.capricorn.org; '.
                               'path=/cgi-bin/database; expires=Thursday, '.
                               '25-Apr-1999 00:40:33 GMT; secure',
      },
    },
    { name => 'API cookie headers', method => 'POST', http_status => 200,
      url => '/api4', input_content => undef,
      http_headers => {
        'Status'            => '200 OK',
        'Content-Type'      => 'application/javascript; charset=iso-8859-1',
        'Content-Length'    => '642',
        'Set-Cookie'        => 'sessionID=xyzzy; domain=.capricorn.org; '.
                               'path=/cgi-bin/database; expires=Thursday, '.
                               '25-Apr-1999 00:40:33 GMT; secure',
      },
    },
    { name => 'Router cookie headers', method => 'POST', http_status => 200,
      url => '/router3',
      input_content => raw_post(
            'http://localhost/router',
            '{"type":"rpc","tid":1,"action":"Qux",'.
            ' "method":"foo_foo","data":["bar"]}'),
      http_headers => {
        'Status'            => '200 OK',
        'Content-Type'      => 'application/json; charset=iso-8859-1',
        'Content-Length'    => '78',
        'Set-Cookie'        => 'sessionID=xyzzy; domain=.capricorn.org; '.
                               'path=/cgi-bin/database; expires=Thursday, '.
                               '25-Apr-1999 00:40:33 GMT; secure',
      },
    },
]
