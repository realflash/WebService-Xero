package WebService::Xero;

use 5.006;
use strict;
use warnings;

=head1 NAME

WebService::Xero - Access Xero Accounting Package Public API

=head1 VERSION

Version 0.13

=cut

our $VERSION = '0.13';


=head1 SYNOPSIS


The Xero API is a RESTful web service and uses the OAuth (v2.0) L<https://oauth.net/2/> protocol to authenticate 3rd party applications.

WebService::Xero aims primarily to simplify the authenticated access to Xero API service end-point by encapuslating the OAuth requirements.

A number of steps are necessary to register your application, documented below. Once completed, this module will allow you to access the API Services.

Xero provides Public Applications only. You can choose whether or not to publish them in the marketplace. The simpler Private Applications are no longer available, and nor are any tenant-wide API keys. You must perform user-specific OAuth2 authentication, which this module implements for you.

This is the simplest possible implementation:

    use WebService::Xero::Agent::PublicApplication;
    use Data::Dump qw(dump);

    $xero = WebService::Xero::Agent::PublicApplication->new( 
													NAME	    => "My Xero App",	# Must match registered name
													CLIENT_ID	=> "<get_this_when_registering>",
													CLIENT_SECRET => "<get_this_when_registering>",
													CACHE_FILE => "/path/to/secured/file/you/want/to/store/tokens/in",
													AUTH_CODE_URL => "http://localhost:3000/auth",	# Web page you make and register the URL of with Xero
																									# In order to receive your grant code and and access tokens
																									# Quick shortcut for this documented below
													);
													
	print $xero->get_auth_url()."\n";									# User clicks this link in their web browser to authenticate your app to their tenant
																		# Once every 90 days
	
	# Once user has authorised your app, Xero will call your AUTH_CODE_URL and append ?code=<your-grant-code>
	# Your web page will have to pass this to your code
	$xero->get_access_token(<your_grant_code>);
	
	# Access code is now stored inside your $xero object and persisted to CACHE_FILE. Should be good for 90 days
	#print dump($xero->do_xero_api_call("https://api.xero.com/connections"));						# Call this once to get a list of tenant IDs
	$xero->{'TENANT_ID'} = "<UUID_of_tenant_you_want_to_interact_with>";							# Then set the tenant you want here
	$contact = $xero->do_xero_api_call("https://api.xero.com/api.xro/2.0/Contacts/<contact_id>");

=head2 DOCUMENTATION

To get started see L<WebService::Xero::Agent::PublicApplication>.

=head2 LIMITS

Xero API call limits are 5,000/day and 60/minute request per organisation limit as described at L<https://developer.xero.com/documentation/guides/oauth2/limits/>.

I have started to work at encpsulating the Xero data objects (Contact, Item, Invoice etc ) and will refine for the next release. The module is usable as of now.

=head1 AUTHORS

Peter Scott, C<< <peter at computerpros.com.au> >>; Ian Gibbs C<igibbs@cpan.org>

=head1 BUGS

Please report any bugs or feature requests to C<bug-WebService-Xero at rt.cpan.org>, or through
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

=over 4

=item * Net::OAuth2 for the OAUTH Code 

L<https://metacpan.org/pod/Net::OAuth2>


=item * Steve Bertrand for advice on Perlmonks 

L<https://metacpan.org/author/STEVEB>

=back

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


