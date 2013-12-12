use strict;
use warnings;
no  warnings 'uninitialized';

use Test::More tests => 55;

use CGI::Test ();       # No need to import ok() from CGI::Test
use CGI::Test::Input ();
use CGI::Test::Input::URL ();
use CGI::Test::Input::Multipart ();

BEGIN { use_ok 'CGI::ExtDirect'; }

my $tests = eval do { local $/; <DATA>; }       ## no critic
    or die "Can't eval DATA: '$@'";

# Testing API
my $ct = CGI::Test->new(
    -base_url => 'http://localhost/cgi-bin',
    -cgi_dir  => 't/cgi-bin',
);

BAIL_OUT "Can't create CGI::Test object" unless $ct;

for my $test ( @$tests ) {
    my $name             = $test->{name};
    my $url              = $test->{url};
    my $method           = $test->{method};
    my $input_content    = $test->{input_content};
    my $http_status_exp  = $test->{http_status};
    my $expected_headers = $test->{http_headers};

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

exit 0;

sub raw_post {
    my $input = shift;

    use bytes;
    my $cgi_input = CGI::Test::Input::URL->new();
    $cgi_input->add_field('POSTDATA', $input);

    return $cgi_input;
}

sub form_post {
    my (%fields) = @_;

    use bytes;
    my $cgi_input = CGI::Test::Input::URL->new();
    for my $field ( keys %fields ) {
        my $value = $fields{ $field };
        $cgi_input->add_field($field, $value);
    };

    return $cgi_input;
}

sub form_upload {
    my ($files, %fields) = @_;

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

__DATA__
[
    { name => 'One parameter', method => 'POST', http_status => 200,
      url => 'http://localhost/cgi-bin/header1.cgi', input_content => undef,
      http_headers => {
        'Status'            => '200 OK',
        'Content-Type'      => 'application/json; charset=utf-8',
        'Content-Length'    => '44',
      },
    },
    { name => 'Two parameters', method => 'POST', http_status => 200,
      url => 'http://localhost/cgi-bin/header2.cgi', input_content => undef,
      http_headers => {
        'Status'            => '200 OK',
        'Content-Type'      => 'application/json; charset=utf-8',
        'Content-Length'    => '44',
      },
    },
    { name => 'Charset override', method => 'POST', http_status => 200,
      url => 'http://localhost/cgi-bin/header3.cgi', input_content => undef,
      http_headers => {
        'Status'            => '200 OK',
        'Content-Type'      => 'application/json; charset=iso-8859-1',
        'Content-Length'    => '44',
      },
    },
    { name => 'Event provider cookie headers', method => 'POST',
      http_status => 200,
      url => 'http://localhost/cgi-bin/header4.cgi', input_content => undef,
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
      url => 'http://localhost/cgi-bin/api4.cgi', input_content => undef,
      http_headers => {
        'Status'            => '200 OK',
        'Content-Type'      => 'application/javascript; charset=iso-8859-1',
        'Content-Length'    => '591',
        'Set-Cookie'        => 'sessionID=xyzzy; domain=.capricorn.org; '.
                               'path=/cgi-bin/database; expires=Thursday, '.
                               '25-Apr-1999 00:40:33 GMT; secure',
      },
    },
    { name => 'Router cookie headers', method => 'POST', http_status => 200,
      url => 'http://localhost/cgi-bin/router3.cgi',
      input_content => raw_post('{"type":"rpc","tid":1,"action":"Qux",'.
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
