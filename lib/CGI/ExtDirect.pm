package CGI::ExtDirect;

use strict;
use warnings;
no  warnings 'uninitialized';       ## no critic

use Carp;
use IO::Handle;
use File::Basename qw(basename);

use RPC::ExtDirect::Config;
use RPC::ExtDirect::API;
use RPC::ExtDirect;

#
# This module is not compatible with RPC::ExtDirect < 3.0
#

die __PACKAGE__." requires RPC::ExtDirect 3.0+"
    if $RPC::ExtDirect::VERSION lt '3.0';

### PACKAGE GLOBAL VARIABLE ###
#
# Version of this module.
#

our $VERSION = '3.00_01';

### PUBLIC CLASS METHOD (CONSTRUCTOR) ###
#
# Instantiate a new CGI::ExtDirect object
#

sub new {
    my $class = shift;

    my %params = @_ == 1 && 'HASH' eq ref $_[0] ? %{ $_[0] }
               :                                  @_
               ;
    
    my $api    = delete $params{api}    || RPC::ExtDirect->get_api();
    my $config = delete $params{config} || $api->config;
    
    # We need a CGI object for input processing
    my $cgi = $params{cgi} || do { require CGI; new CGI };

    # Debug flag defaults to off
    $config->debug( $params{debug} ) if $params{debug};

    my $self = bless {
        config  => $config,
        api_obj => $api,
        cgi     => $cgi,
        %params,
    }, $class;

    return $self;
}

### PUBLIC INSTANCE METHOD ###
#
# Returns API definition for ExtDirect, along with headers
#

sub api {
    my ($self, @headers) = @_;

    # Get the API JavaScript
    my $js = eval {
        $self->api_obj->get_remoting_api(
            config => $self->config,
            env    => $self->cgi,
        )
    };

    # If JS API call failed, return error headers
    # What exactly went wrong is not too relevant here
    return $self->error_headers(@headers) if $@;

    # If API call succeed, return application/javascript with 200 OK
    my $content_type = 'application/javascript';
    my $http_status  = '200 OK';

    # And we need content length, too (in octets)
    my $content_length = do { use bytes; length $js; };

    # Munge the headers passed on us
    my @real_headers = $self->_munge_headers($content_type,
                                             $http_status,
                                             $content_length,
                                             @headers);

    # Finally, compile HTTP response
    my $response = $self->cgi->header(@real_headers) .
                   $js;

    return $response;
}

### PUBLIC INSTANCE METHOD ###
#
# Routes the action request and returns HTTP response with headers
#

sub route {
    my ($self, @headers) = @_;

    # If any but POST method is used, just throw an error
    return $self->error_headers(@headers)
        if $self->cgi->request_method() ne 'POST';

    # Try to distinguish between raw POST and form call (Ugh)
    my $router_input = $self->_extract_post_data();

    # When extraction fails, undef is returned
    return $self->error_headers(@headers)
        unless defined $router_input;
    
    my $config       = $self->config;
    my $api          = $self->api_obj;
    my $router_class = $config->router_class;
    
    eval "require $router_class";
    
    my $router = $router_class->new(
        config => $config,
        api    => $api,
    );

    # Routing requests is safe (Router won't croak under torture)
    my $result = $router->route($router_input, $self->cgi);

    my ($content_type, $http_body, $content_length);

    $content_type   = $result->[1]->[1];
    $content_length = $result->[1]->[3];
    $http_body      = $result->[2]->[0];
    my $http_status = '200 OK';

    # Munge the headers passed on us
    my @real_headers = $self->_munge_headers($content_type,
                                             $http_status,
                                             $content_length,
                                             @headers);

    # Finally, compile HTTP response
    my $response = $self->cgi->header(@real_headers) .
                   $http_body;

    return $response;
}

### PUBLIC INSTANCE METHOD ###
#
# Queries Event providers for events, returning serialized stream.
#

sub poll {
    my ($self, @headers) = @_;

    # Only GET and POST methods are supported for polling
    return $self->error_headers(@headers)
        if $self->cgi->request_method() !~ / \A (GET|POST) \z /xms;
    
    my $config         = $self->config;
    my $api            = $self->api_obj;
    my $provider_class = $config->eventprovider_class;
    
    eval "require $provider_class";
    
    my $provider = $provider_class->new(
        config => $config,
        api    => $api,
    );

    # Polling for Events is safe
    my $http_body = $provider->poll($self->cgi);

    # Gather variables for HTTP response
    my $content_type = 'application/json';
    my $http_status  = '200 OK';

    # And we need content length, too (in octets)
    my $content_length = do { use bytes; length $http_body; };

    # Munge the headers passed on us
    my @real_headers = $self->_munge_headers($content_type,
                                             $http_status,
                                             $content_length,
                                             @headers);

    # Finally, compile HTTP response
    my $response = $self->cgi->header(@real_headers) .
                   $http_body;

    return $response;
}

### PRIVATE INSTANCE METHOD ###
#
# Returns error HTTP header string. There is not much sense in
# returning HTTP body as well since Ext.Direct calls are automated
# and there is nobody to see error messages anyway.
#

sub error_headers {
    my ($self, @headers) = @_;

    # Get ourselves a set of brand new CGI headers
    my @cgi_headers = $self->_munge_headers('text/html',
                                            '500 Internal Server Error',
                                            0,
                                            @headers);

    return $self->cgi->header(@cgi_headers);
}

### PUBLIC INSTANCE METHODS ###
#
# Read-write accessors
#

RPC::ExtDirect::Util::Accessor->mk_accessors(
    simple => [qw/ config api_obj cgi /],
);

############## PRIVATE METHODS BELOW ##############

### PRIVATE INSTANCE METHOD ###
#
# Munges CGI headers so that they become what we need
#

sub _munge_headers {
    my ($self, $content_type, $http_status,
               $content_length, @headers) = @_;

    # Default charset is UTF-8
    my $charset = 'utf-8';

    # First form is no additional headers passed on us, easy one
    # Second form includes only one parameter and that's content type
    # Third form includes both content type and HTTP status
    # Last form is hash of headers but we'd better check that anyway
    #
    # If that's the case, just override it and that's that
    #
    return (
             '-type'           => $content_type,
             '-status'         => $http_status,
             '-charset'        => $charset,
             '-content_length' => $content_length,
           )
        if  @headers == 0 || @headers == 1 ||
           (@headers == 2 && $headers[0] !~ / \A - /msx) ||
           (@headers > 2 && ((@headers % 2) != 0));

    # Finally we've got a hash of header parameters
    my %cgi_headers = @headers;

    # Interesting are the headers we need to deal with
    my %interesting_item = (
        '-type'           => qr/ \A -? (content [-_])? type \z /ixms,
        '-status'         => qr/ \A -? status \z               /ixms,
        '-charset'        => qr/ \A -? charset \z              /ixms,
        '-content_length' => qr/ \A -? content [-_] length \z  /ixms,
    );

    # Normalize them headers we need, don't touch the others
    HEADER_ITEM:
    for my $item ( keys %interesting_item ) {
        my $pattern = $interesting_item{ $item };

        # First find all occurences of the interesting item
        my @found_items = grep { /$pattern/ } keys %cgi_headers;
        next HEADER_ITEM unless @found_items;

        # Then take *first* value -- we don't care about duplicates
        # and they should not have happened anyway, so there
        my $value = $cgi_headers{ $found_items[0] };

        # Delete all occurences of the item in question
        delete @cgi_headers{ @found_items };

        # Finally, place normalized item back in hash
        $cgi_headers{ $item } = $value;
    };

    # Forcibly replace the ones we need (even if they were not there)
    $cgi_headers{ '-type' }           = $content_type;
    $cgi_headers{ '-status' }         = $http_status;
    $cgi_headers{ '-content_length' } = $content_length;

    # If they passed charset, then they probably know what they're doing
    $cgi_headers{ '-charset' } = $charset
        unless exists $cgi_headers{ '-charset' };

    # We don't need to touch anything else
    return %cgi_headers;
}

### PRIVATE INSTANCE METHOD ###
#
# Deals with intricacies of POST-fu and returns something suitable to
# feed to Router (string or hashref, really). Or undef if something
# goes too wrong to recover.

my @STANDARD_KEYWORDS
    = qw(action method extAction extMethod extTID extUpload extType); 
my %STANDARD_KEYWORD = map { $_ => 1 } @STANDARD_KEYWORDS;

sub _extract_post_data {
    my ($self) = @_;

    # We need CGI object here real bad
    my $cgi = $self->cgi;

    # The smartest way to tell if a form was submitted that *I* know of
    # is to look for 'extAction' and 'extMethod' keywords in CGI params.
    my %keyword = map { $_ => 1 } $cgi->param();
    my $is_form = exists $keyword{ extAction } &&
                  exists $keyword{ extMethod };

    # If form is not involved, it's easy: just return POSTDATA (or undef)
    if ( !$is_form ) {
        my $postdata = $cgi->param('POSTDATA');
        return $postdata ne '' ? $postdata
               :                 undef
               ;
    };

    # If any files are attached, extUpload will contain 'true'
    my $has_uploads = $cgi->param('extUpload') eq 'true';

    # Here file uploads data is stored
    my @_uploads = ();

    # Now if the form IS involved, it gets a little bit complicated
    PARAM:
    for my $param ( keys %keyword ) {
        # Defang CGI's idiosyncratic way of returning multi-valued params
        my @values = $cgi->param( $param );
        $keyword{ $param } = @values == 0 ? undef
                           : @values == 1 ? $values[0]
                           :                [ @values ]
                           ;

        # Try to see if $param is a field with associated file upload
        # Skip the standard ones first, of course
        next PARAM if $STANDARD_KEYWORD{ $param } || !$has_uploads;

        # Look for file uploads in this field
        my @field_uploads = $self->_parse_uploads($cgi, $param);

        # Found some, add them to general stash and kill the field
        if ( @field_uploads ) {
            push @_uploads, @field_uploads;
            delete $keyword{ $param };
        };
    };

    # Remove extType because it's meaningless later on
    delete $keyword{ extType };

    # Fix TID so that it comes as number (JavaScript is picky)
    $keyword{ extTID } += 0 if exists $keyword{ extTID };

    # Now add files to hash, if any
    $keyword{ '_uploads' } = \@_uploads if @_uploads;

    return \%keyword;
}

### PRIVATE INSTANCE METHOD ###
#
# Parses CGI form input field looking for file uploads
#

sub _parse_uploads {
    my ($self, $cgi, $param) = @_;

    # CGI returns "lightweight file handles", or undef
    my @file_handles = $cgi->upload($param);

    # Empty list means no uploads for this field
    return unless grep { defined $_ } @file_handles;

    # Despite what CGI documentation says, the values returned
    # as "file names" are actually some kind of key handles
    my @file_keys = $cgi->param($param);

    # Here file uploads get collected
    my @uploads = ();

    # Collect the info we need to repackage it in consistent way
    FILE:
    for my $key ( @file_keys ) {
        # First take a closer look at this "blah-blah handle"
        my $file_handle = shift @file_handles;

        # undef would mean there was an upload error (timeout perhaps)
        # Following HTTP POST logic, when one upload breaks that
        # would mean all subsequent uploads in this POST are also
        # broken.
        # We can't do anything about it anyway so just stop trying.
        last FILE unless defined $file_handle;

        # In CGI.pm < 3.41, "lightweight handle" object doesn't support
        # returning IO::Handle so we do it manually to avoid problems
        my $io_handle = IO::Handle->new_from_fd(fileno $file_handle, '<');

        # We also need a lot of info about the file (if provided)
        my $upload_info = $cgi->uploadInfo($key);
        my $temp_file   = $cgi->tmpFileName($key);
        my $file_type   = $upload_info->{'Content-Type'};
        my $file_name   = $self->_get_file_name($upload_info);
        my $file_size   = $self->_get_file_size($io_handle);
        my $base_name   = basename($file_name);

        # Now instead of "blah-blah handle" we have a hashref full of info
        push @uploads, {
            type     => $file_type,
            size     => $file_size,
            path     => $temp_file,
            handle   => $io_handle,
            basename => $base_name,
            filename => $file_name,
        };
    };

    return @uploads;
}

### PRIVATE INSTANCE METHOD ###
#
# Tries hard to extract file name from multipart form guts
#

sub _get_file_name {
    my ($self, $upload_info) = @_;

    # Pluck file name from Content-Disposition string
    my ($file_name)
        = $upload_info->{'Content-Disposition'} =~ /filename="(.*?)"/;

    # URL unescape it
    $file_name =~ s/%([\dA-Fa-f]{2})/pack("C", hex $1)/eg;

    return $file_name;
}

### PRIVATE INSTANCE METHOD ###
#
# Enquiries IO::Handle supplied by CGI for file size
#

sub _get_file_size {
    my ($self, $handle) = @_;

    # Fall through in case $handle is invalid
    return unless $handle;

    return ($handle->stat)[7];
}

1;

__END__

=pod

=head1 NAME

CGI::ExtDirect - Ext.Direct remoting interface for CGI applications

=head1 SYNOPSIS

=head2 API definition

In api.cgi:

    use CGI::ExtDirect;
    use RPC::ExtDirect::API api_path     => '/extdirect_api',
                            router_path  => '/extdirect_router',
                            poll_path    => '/extdirect_events',
                            remoting_var => 'Ext.app.REMOTING_API',
                            polling_var  => 'Ext.app.POLLING_API',
                            namespace    => 'myApp',  # Defaults to empty
                            auto_connect => 0,
                            no_polling   => 0,
                            debug        => 0,
                            before       => \&global_before_hook,
                            after        => \&global_after_hook,
                            ;
    
    use My::ExtDirect::Published::Module::Foo;
    use My::ExtDirect::Published::Module::Bar;
    
    my $direct = CGI::ExtDirect->new();
    
    print $direct->api();      # Prints full HTTP response

=head2 Routing requests

In router.cgi:

    use CGI::ExtDirect;
    
    use My::ExtDirect::Published::Module::Foo;
    use My::ExtDirect::Published::Module::Bar;
    
    my $debug   = 1;  # Optional debugging flag
    my %headers = (   # Optional CGI headers
        -charset => 'iso-8859-1',
        -nph     => 1,
        -cookie  => $cookie,
    );
    
    my $direct = CGI::ExtDirect->new( debug => $debug );
    
    print $direct->route(%headers);    # Prints full HTTP response

=head2 Providing Event polling service

In poll.cgi:

    use CGI;
    use CGI::ExtDirect;
    
    use My::ExtDirect::Event::Provider1;
    use My::ExtDirect::Event::Provider2;
    
    my $debug = 1; 
    my $cgi   = CGI->new;
    
    # do something with $cgi but do not print headers
    ...
    
    my $direct = CGI::ExtDirect->new( cgi => $cgi, debug => $debug );
    
    print $direct->poll();

=head1 DESCRIPTION

This module provides RPC::ExtDirect gateway implementation for CGI
compatible HTTP servers. It can be used wth Perl versions 5.6 and
newer in about any environment; it was tested successfully with
Apache, pure Perl server based on HTTP::Server::Simple and various
other HTTP servers.

You can change default configuration options by passing corresponding
parameters like shown above. For the meaning of parameters, see
L<RPC::ExtDirect::API> documentation.

Note that Ext.Direct specification requires server side implementation
to return diagnostic messages only when debugging is explicitly turned
on. This is why C<debug> flag defaults to 'off' and CGI::ExtDirect
returns generic error messages that do not contain any details as to
where and what error has happened.

=head1 METHODS

=over 4

=item new($arguments)

Creates a new CGI::ExtDirect object. $arguments is an optional hashref
with the following options:

=over 8

=item cgi

Instantiated CGI or similar object.

=item debug

Debug flag, defaults to off. See the note above.

=back

=item api(%headers)

Creates JavaScript code with server side Action and Method declarations
and prints it to default output handle along with HTTP headers. You can
specify additional headers in CGI format: NPH, cookies, whatever; they
will be passed to CGI->header() which is used to form HTTP header part.

Some of the headers, namely Content-Type, Content-Length and Status, are
always overridden to provide client side with adequate response. Default
Charset is UTF-8; however if you pass -charset header CGI::ExtDirect will
honor it. It is implied that you should only do this when you clearly know
what you are doing.

Other headers are passed along to CGI->header() unchanged.

=item route(%headers)

Accepts Ext.Direct requests, dispatches them, collects results and prints
them back as serialized stream.

%headers are treated the same way as in api(), see above.

=item poll(%headers)

Queries Event provider Methods registered with RPC::ExtDirect as
pollHandlers for events, collects them and returns back serialized stream.

%headers are treated the same way as in api(), see above.

=back

=head1 DEPENDENCIES

CGI::ExtDirect is dependent on the following modules:
    L<RPC::ExtDirect>, L<JSON>, L<Attribute::Handlers>.

=head1 SEE ALSO

For explanation of RPC::ExtDirect attributes, see L<RPC::ExtDirect>. For
more detail on API options, see L<RPC::ExtDirect::API>.

For more information on Ext.Direct API see specification:
L<http://www.sencha.com/products/extjs/extdirect/> and documentation:
L<http://docs.sencha.com/ext-js/4-0/#!/api/Ext.direct.Manager>.

See included Ext JS examples for ideas on what Ext.Direct is and how to
use it in CGI applications.

=head1 ACKNOWLEDGEMENTS

I would like to thank IntelliSurvey, Inc for sponsoring my work
on version 2.0 of RPC::ExtDirect suite of modules.

The tiny but CGI-capable HTTP server used to provide working examples
is (c) 2002-2004 by Hans Lub, <hlub@knoware.nl>. It is called p5httpd
and can be found here: L<http://utopia.knoware.nl/~hlub/rlwrap/>

=head1 BUGS AND LIMITATIONS

Hooks functionality depend on RPC::ExtDirect 2.0 which is incompatible
with Perls older than 5.12.

There are no known bugs in this module. Use github tracker to report
bugs (better way) or just drop me an e-mail. Patches are welcome.

=head1 AUTHOR

Alexander Tokarev E<lt>tokarev@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2011-2012 Alexander Tokarev.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself. See L<perlartistic>.

Included Ext JS examples are copyright (c) 2011, Sencha Inc. Example code
is used and distributed under GPL 3.0 license as provided by Sencha Inc.
See L<http://www.sencha.com/license>. Ext JS is available for download at
L<http://www.sencha.com/products/extjs/>

=cut

