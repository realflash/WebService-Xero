package WebService::Xero::Agent::PublicApplication;

use 5.006;
use strict;
use warnings;
use parent ('WebService::Xero::Agent');
use Log::Log4perl;
use Data::Dump qw(dump);
use Digest::MD5 qw( md5_base64 );
use URI::Encode qw(uri_encode uri_decode );
use Data::Random qw( rand_chars );
use Net::OAuth2 0.67;
use Data::Validate::URI qw(is_uri);

=head1 NAME

WebService::Xero::Agent::PublicApplication - Connects to Xero Public Application API 

=head1 VERSION

Version 0.13

=cut

our $VERSION = '0.13';
my $_log = Log::Log4perl->get_logger("WebService::Xero::PublicApplication");

=head1 SYNOPSIS

See L<WebService::Xero> for code. The steps to use this module are:

=over

=item *
Register application on the Xero Developer portal

=item 1
Create an instance of this module configured with various bits of auth information

=item 1
Have a user authorise the application to a Xero tenant, grabbing the grant code as you do it

=item 1
Give the grant code to this module so that it can get credentials

=item 1
Use this module to query the various Xero APIs

=back

This module helps you as much as it can. The details of each step are below.

=head2 REGISTER APPLICATION

Hello.


=head1 METHODS

=cut

sub _validate_agent 
{
	my ( $self  ) = @_;

	unless($self->{CLIENT_ID}){ $self->_error("No client ID specified in constructor"); return $self; }
	unless($self->{CLIENT_SECRET}) { $self->_error("No client secret specified in constructor"); return $self; }
	unless($self->{CACHE_FILE}){ $self->_error("No cache file specified in constructor"); return $self; }
	unless($self->{AUTH_CODE_URL}) { $self->_error("No auth code URL specified in constructor"); return $self; }
	unless(length($self->{CLIENT_ID}) >= 32) { $self->_error("Client ID too short"); return $self; }
	unless(length($self->{CLIENT_SECRET}) >= 48) { $self->_error("Client secret too short"); return $self; }
	unless(is_uri($self->{AUTH_CODE_URL})) { $self->_error("Auth code URL is not a valid HTTP or HTTPS URL"); return $self; }
	#~ $_log->trace("Constructor got these params: ".dump(@_));

	return $self;
}


=head2 get_request_token()

  Takes the callback URL as a parameter which is used to create the request for
  a request token. The request is submitted to Xero and if successful this
  method eturns the Token and sets the 'login_url' property of the agent.

  Assumes that the public application API configuration is set in the agent ( CONSUMER KEY and SECRET )

=cut 

sub get_request_token ## FOR PUBLIC APP (from old Xero::get_auth_token)
{
  ## talks to Xero to get an auth token 
  my ( $self, $my_callback_url ) = @_;
  my $data = undef;

  
  my $access = Net::OAuth->request("request token")->new(
   'version' => '1.0',
   'request_url' => 'https://api.xero.com/oauth/RequestToken?oauth_callback=' . uri_encode( $my_callback_url ),
    callback =>  $my_callback_url,
    client_id     => $self->{CLIENT_ID},
    client_secret  => $self->{CLIENT_SECRET},
    request_method   => 'GET',
    signature_method => 'HMAC-SHA1',
    timestamp        => time,
    nonce            => 'ccp' . md5_base64( join('', rand_chars(size => 8, set => 'alphanumeric')) . time ), #$nonce
  );
  $access->sign();
  #warn $access->to_url."\n";
  my $res = $self->{ua}->get( $access->to_url  ); ## {oauth_callback=> uri_encode('http://localhost/')}
  if ($res->is_success)
  {
    my $response = $res->content();
    #warn("GOT A NEW auth_token ---" . $response);
    if ( $response =~ /oauth_token=([^&]+)&oauth_token_secret=([^&]+)&oauth_callback_confirmed=true/m)
    {
      $self->{oauth_token} = $1;#, "\n";
      $self->{oauth_token_secret} = $2;#, "\n";

      $self->{login_url} = 'https://api.xero.com/oauth/Authorize?oauth_token='
            . $self->{oauth_token}
            . '&oauth_callback='
            . $my_callback_url;

      $self->{status} = 'GOT REQUEST TOKEN AND GENERATED Xero login_url that includes callback';
      return $self->{oauth_token};
    }
  } 
  else 
  {
    return $self->_error("ERROR: " . $res->content);
  }
}
#####################################

=head2 do_xero_api_call()

  INPUT PARAMETERS AS A LIST ( NOT NAMED )

* $uri (required)    - the API endpoint URI ( eg 'https://api.xero.com/api.xro/2.0/Contacts/')
* $method (optional) - 'POST' or 'GET' .. PUT not currently supported
* $xml (optional)    - the payload for POST updates as XML

  RETURNS

    The response is requested in JSON format which is then processed into a Perl structure that
    is returned to the caller.

=head2 The OAuth Dance

Public Applications require the negotiation of a token by directing the user to Xero to authenticate and accepting the callback as the
user is redirected to your application.

To implement you need to persist token details across multiple user web page requests in your application.

To fully understand the integration implementation requirements it is useful to familiarise yourself with the terminology.

=head3 OAUTH 1.0a TERMINOLOGY

=begin TEXT

User              A user who has an account of the Service Provider (Xero) and tries to use the Consumer. (The API Application config in Xero API Dev Center .)
Service Provider  Service that provides Open API that uses OAuth. (Xero.)
Consumer          An application or web service that wants to use functions of the Service Provider through OAuth authentication. (End User)
Request Token     A value that a Consumer uses to be authorized by the Service Provider After completing authorization, it is exchanged for an Access Token. 
                    (The identity of the guest.)
Access Token      A value that contains a key for the Consumer to access the resource of the Service Provider. (A visitor card.)

=end TEXT


=head2 Authentication occurs in 3 steps (legs):

=head3 Step 1 - Get an authorisation code

    use WebService::Xero::Agent::PublicApplication;

    my $xero = WebService::Xero::Agent::PublicApplication->new( CLIENT_ID    => 'YOUR_OAUTH_CLIENT_ID', # Get this from Xero Developer site
                                                          CLIENT_SECRET => 'YOUR_OAUTH_CLIENT_SECRET',  # Get this from Xero Developer site
                                                          CACHE_FILE => '/tmp/myapp.cache',				# Protect this as it will contain security tokens (but not your client creds)
                                                          AUTH_CODE_URL    => 'http://127.0.0.1:3000'	# or a URL to some page you create in your existing web app
                                                          );
    my $url = $xero->get_auth_url(); 											# This retrieves the URL to give to the user to visit
    print "Visit this URL to authorise this app to a Xero tenant: $url\n";		# or embed it in a web page somewhere, or send as a redirect

=head3 Step 2 - Redirect User

    user click on link to $xero->{login_url} which takes them to Xero - when they authorise your app they are redirected back to your callback URL (C)(D)


=head3 Step 3 - Swap a Request Token for an Access Token

    The callback URL includes extra GET parameters that are used with the token details stored earlier to obtain an access token.
    
   my $oauth_verifier = $cgi->url_param('oauth_verifier');
   my $org            = $cgi->param('org');
   my $oauth_token    = $cgi->url_param('oauth_token');

   $xero->get_access_token( $oauth_token, $oauth_verifier, $org, $stored_token_secret, $stored_oauth_token ); ## (E)(F)

=head3 Step 4 - Access the Xero API using the access token 

    my $contact_struct = $xero->do_xero_api_call( 'https://api.xero.com/api.xro/2.0/Contacts' );  ## (G)


=head2 Other Notes

The access token received will expire after 30 minutes. If you want access for longer you will need the user to re-authorise your application.

Xero API Applications have a limit of 1,000/day and 60/minute request per organisation.

Your application can have access to many organisations at once by going through the authorisation process for each organisation.

=head3 Xero URLs used for authorisation and using the API

Get an Unauthorised Request Token:  https://api.xero.com/oauth/RequestToken
Redirect a user:  https://api.xero.com/oauth/Authorize
Swap a Request Token for an Access Token: https://api.xero.com/oauth/AccessToken
Connect to the Xero API:  https://api.xero.com/api.xro/2.0/


=head1 AUTHOR

Peter Scott, C<< <peter at computerpros.com.au> >>; Ian Gibbs C<igibbs@cpan.org>

=head1 BUGS

Please report any bugs or feature requests to C<bug-webservice-xero at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=WebService-Xero>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

You can also look for information at:

=over 4

=item * Xero Developer Documentation Home

L<https://developer.xero.com/>

=item * Xero API Reference

L<https://developer.xero.com/documentation/api/accounting/overview>

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=WebService-Xero>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/WebService-Xero>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/WebService-Xero>

=item * Search CPAN

L<http://search.cpan.org/dist/WebService-Xero/>

=back

=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2016-2018 Peter Scott.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.




=begin HTML

<p><img src="https://oauth.net/core/diagram.png"></p>

=end HTML

=cut

1; # End of WebService::Xero
