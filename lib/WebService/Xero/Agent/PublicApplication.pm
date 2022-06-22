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

=over 4

=item 1. Set up web page for redirect

=item 2. Register application on the Xero Developer portal

=item 2. Create an instance of this module configured with various bits of auth information

=item 3. Have a user authorise the application to a Xero tenant, grabbing the grant code as you do it

=item 4. Give the grant code to this module so that it can get an access token

=item 5. Set the tenant ID

=item 6. Use this module to query the various Xero APIs

=back

This module helps you as much as it can. The details of each step are below.

=head1 SET UP

=head2 1. Set up web page for redirect

There are lots of good web pages describing how oAuth 2 works so we will not expound unecessarily here; the highlights for this step are:

=over 4

=item 1. User tells Xero that it's OK for your app to interact with their data, and specifies which Xero tenant(s) it can access

=item 2. Xero gives user a grant code representing this permission, and tells the user's browser to which URI (controlled by you) to go to hand it over (the Redirect URI)

=item 3. The user's browser automatically goes to the redirect URI, which is controlled by you. Your URI accepts the grant code and then uses it to perform actions on behalf of the user.

=back

So, you need a web page that can have this conversation with the user, accept the grant code, and pass it on to your Perl code that uses this module. The authorisation provided by the user to your application lasts 90 days; after this any authorisation tokens stored by your application/this module will be deemed invalid by Xero and you will have to ask the user to authenticate the access again. If you are doing some kind of backend process only "used" by one Xero ID on behalf of a whole Xero tenant, this already is going to feel like a whole load of crap you didn't want to deal with, and you are now going to go looking for an alternative module or alternative authorisation process that uses some kind of permanent API key. We'll see you back here shortly.

If you are building a multi-user web app which will regularly deal with new users and re-authorising existing users you are clearly going to build this web page into your larger app. If you are a planning a one time data export you will want a temporary easy solution to this, which we provide below. The redirect URI needs to be accessible to the user's computer; the one the user uses to carry out the authorisation of your app in Xero. So your web page doesn't have to be internet-accessible; it could be on the same local network as the user authorising, or even running on localhost on the user's computer (see below). Obviously the computer the user uses to authorise needs to be able to access Xero across the internet AND your Redirect URI at the same time.

Your redirect URI will called with a GET request, with the grant code appended as a URI param:

	GET http://yourwebserver.com/callback.cgi?code=9srN6sqmjrvG5bWvNB42PCGju0TFVV

Your web page needs to pop off that code, and then give it to this module when asking for an access token to be retrieved on behalf of the user (see L</get_access_token>).

Once you have decided how you are going to do this, you will know what your Redirect URI will be. You need this to register your application with Xero. For a quick hack, see C<examples/oauth2_redirect.pl>, which you can run once to authorise your app and then store credentials. It uses a Redirect URI of C<http://localhost:3000/callback>

Your Redirect URI B<MUST> have a URI fragment: 

	https://yourwebserver.com

is not OK, but 

	https://yourwebserver.com/callback

is. Your Redirect URI B<MUST NOT> use the IP 127.0.0.1; 

	https://127.0.0.1/callback

is not OK, but 

	https://localhost/callback

is. At the time of writing these things aren't documented by Xero, but if you fall foul of them their firewall will reject your authorisation attempts because it will think you are attempting to perform a client side script injection attack. Don't ask how we know. 

=head2 2. Register application

Your application must be registered with Xero in order to perform API calls on behalf of Xero users. Registering gets you an oAuth Client ID and Client Secret that your application can use to authenticate to the API. For the avoidance of doubt, you will be registering your application which may happen to use this library. You are not registering this library. You will give this library the credentials assigned to your application by Xero. 

Registering your application with Xero does not make it available to members of the public, and does not publish it in the Xero marketplace. That is an option you can choose later, but you can equally keep it as an internal application.

You will need a Xero ID to register your application. There is a 30-day free Xero trial. Whether your Xero ID will persist if you don't then purchase a Xero subscription we couldn't currently say. Reports welcome.

Here are the steps for registering your application:

=over 4 

=item 1. Register a Xero ID and/or log in at L<https://developer.xero.com/>

=item 2. Go to L<https://developer.xero.com/app/manage> and click B<New app>

=item 3. Enter the name of your app. It can't have 'Xero' in it. 

=item 4. Set the B<Integration type> to B<Web app>

=item 5. Set a URL for your company or app. It probably doesn't matter if you make this up. 

=item 6. Set the B<Redirect URI> you have chosen to use.

=item 7. Agree the Ts&Cs and B<Create app>.

=item 8. You will now be in the Configuration page for your new app. Click B<Configuration> on the left-hand side. Copy the B<Client id> and save it

=item 9. B<Generate a secret> and copy and save it

=back

=head2 3. Authorise a Xero tenant

Now Xero knows about your app, you can now have a user connect their tenant to your app. For this section we will assume that you are using your own Xero ID.

=over 4

=item 1. Run your web server so that your Redirect URI is ready and listening

=item 2. Create a WebService::Xero object and call get_auth_url()

	my $xero = WebService::Xero::Agent::PublicApplication->new( 
		CLIENT_ID	=> "4DD95A6412A547D3883804C4647F8B2E", 			# Get this from Xero when registering
		CLIENT_SECRET => "G2ZQBLHonZqi7lwPkHBvhYdeS2b7k7RGZgZ-FWH6ZkgQvNhn",	# Get this from Xero when registering
		CACHE_FILE => $ENV{"HOME"}.'/.WebServiceXero.cache',			# Per user!
		AUTH_CODE_URL => "http://localhost:3000/callback",			# Must match what you registered with Xero
	);
	print $xero->get_auth_url()."\n";

=item 3. Go to the URL with your web browser

=item 4. Select the Xero tenant(s) that you want to access data in (or your user will do this on your behalf and click B<Continue>

=item 5. Your browser will then call your Redirect URI and deliver your grant code.

=back

The grant code is only valid for 5 minutes, so you really need your Redirect URI web page to get the grant code to this module programmatically.

=head2 4. Use the grant code to get an access token

Use this to get an access token:

	$xero->get_access_token(<grant_code>);
	
This module will contact the Xero authorisation endpoint and exhange the grant code for an access token, and store it in the cache file you specified. This access token expires, but this module will handle refreshing it automatically, up to the 90 day expiry. After that authorisation will start failing. More methods to help with that will be forthcoming. This module isn't yet old enough to see what happens when the 90 days is up. 

The method returns the access token but only for fun. You don't need to do anything with it; it is stored int he object and also persisted to the cache file. The access token stored in the cache file is specific to the user that authorised your application. It will allow to access onlt the tenants you specified earlier. If you authorise another user using the same cache file, the original tokens will be overwritten and lost. Use one cache file per user.

=head2 5. Set the tenant ID

With your access token stored in the cache file, you can now call methods provided by this module and start interacting with the Xero API. All API calls must specify the tenant ID that you wish to interact with. The module will do this on your behalf once you have set it. This is done like this:

	$xero->{'TENANT_ID'} = <tenant-id>;
	
Until you do this, this module will not allow you to call anything, except this one call that lists all the tenants the stored access key has access to:

	use Data::Dump qw(dump);
	
	dump($xero->do_xero_api_call("https://api.xero.com/connections"));
	
This will print an array ref listing all the tenants you are authorised to, including their IDs:

	[
	  {
		authEventId => "d2192435-d53a-43f6-b4a8-225442896e50",
		createdDateUtc => "2022-06-22T15:13:37.4993980",
		id => "48d653d3-db29-4903-9a6f-55b4566912a7",
		tenantId => "1aa95d4b-1593-4693-8ba3-be4458927be7",
		tenantName => "MY CORP LIMITED",
		tenantType => "ORGANISATION",
		updatedDateUtc => "2022-06-22T15:13:37.5012450",
	  },
	]

It is the C<tenantId> that you need.

=head2 6. Us this module

Well done if you made it this far. Now you can finally use this module and get data from the Xero API:

	$xero->do_api_call("https://api.xero.com/api.xro/2.0/Organisation"));
	
will return a nice big blob of stuff about the Xero tenant. You can make any call specified in the L<Xero API|https://developer.xero.com/documentation/api/accounting/overview>.

=head1 METHODS

See L<WebService::Xero::Agent>

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

#####################################

=head1 AUTHOR

Peter Scott, C<< <peter at computerpros.com.au> >>; Ian Gibbs C<<igibbs@cpan.org>>

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

=cut

1; # End of WebService::Xero
