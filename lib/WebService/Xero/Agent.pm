package WebService::Xero::Agent;


use 5.006;
use strict;
use warnings;
use Carp;
use Data::Dump qw(dump);
use LWP::UserAgent;
use HTTP::Request;
use Mozilla::CA;									# Needed for LWP HTTPS
use Storable;
use JSON;
use Digest::MD5 qw( md5_base64 );
use URI::Encode qw(uri_encode uri_decode );
use Net::OAuth2::Profile::WebServer 0.67;
use Try::Tiny;
use WebService::Xero::Organisation;
use Scalar::Util qw(openhandle);
use File::Temp qw(tempfile);

=head1 NAME

WebService::Xero::Agent - Base Class for API Connections

=head1 VERSION

Version 0.13

=cut

our $VERSION = '0.13';

=head1 SYNOPSIS

This is the base class for the Xero API agents that integrate with the Xero Web Application APIs.

You should not need to use this directly but should use the derived class.

see the following for usage examples:

  perldoc WebService::Xero::Agent::PublicApplication



=head1 METHODS

=head2 new()

  default base constructor - includes properties used by child class.

=cut

sub new 
{
  my ( $class, %params ) = @_;

    my $self = bless 
    {
      NAME           => $params{NAME} || 'Unnamed Application',
      CLIENT_ID   => $params{CLIENT_ID} || '',
      CLIENT_SECRET => $params{CLIENT_SECRET} || "",
      CACHE_FILE => $params{CACHE_FILE} || "",
      AUTH_CODE_URL => $params{AUTH_CODE_URL} || "",
      TENANT_ID => $params{TENANT_ID} || "",
      ua              => LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 },),
      _status           => undef,
      _oauth           => undef,
      _cache           => undef,
    }, $class;
    
    $self->_validate_agent();	## derived classes to validate required properties
								## This should have croaked if anything was wrong with our constructor params
								
	# Initialise OAuth object
	$self->{_oauth} = Net::OAuth2::Profile::WebServer->new( name => 'Xero',
														client_id => $self->{CLIENT_ID},
														client_secret => $self->{CLIENT_SECRET},
														scope => 'openid profile email accounting.transactions accounting.attachments accounting.settings accounting.contacts offline_access',
														redirect_uri => $self->{AUTH_CODE_URL},
														authorize_url => 'https://login.xero.com/identity/connect/authorize',
														access_token_url => 'https://identity.xero.com/connect/token',
														refresh_token_url => 'https://identity.xero.com/connect/token',
														secrets_in_params => 0);

	# Check cache file is readable and writeable. Could well be some shenanigans here if run in a web server context, and this should flush any errors out earlier
	if(-e $self->{CACHE_FILE})
	{
		unless(-r $self->{CACHE_FILE}){ return $self->_error("Specified cache file exists and is not readable for file system access reasons") }
		unless(-w $self->{CACHE_FILE}){ return $self->_error("Specified cache file exists and is not writeable for file system access reasons") }
		try
		{
			$self->{_cache} = retrieve($self->{CACHE_FILE});
		} 
		catch
		{
			return $self->_error("Couldn't retrieve existing cache file: $_");
		};
		unless($self->{_cache})
		{
			return $self->_error("Couldn't retrieve existing cache file: reason unknown");
		}
		else
		{
			$self->{_cache}->{WebService_Xero_version} = $VERSION;		# Store our version
			if($self->{_cache}->{access_token})
			{
				$self->{_cache}->{access_token} = Net::OAuth2::AccessToken->session_thaw($self->{_cache}->{access_token}, profile => $self->{_oauth});	# Unthaw into active token ready for use
				$self->{_cache}->{access_token}->auto_refresh(1);			# Auto refresh it if it is needed
			}
		}
	}
	else
	{	# Create a cache and save it now to see if it blows up
		$self->{_cache} = { WebService_Xero_version => $VERSION };
		try
		{
			store $self->{_cache}, $self->{CACHE_FILE};
		}
		catch
		{	# Write was attempted and went wrong somehow
			return $self->_error("Couldn't write to cache file: $_");
		};
	}

    return $self;
}


=head2 _validate_agent()

	To be implemented in derived classes to validate the configuration of the agent.

=cut

sub _validate_agent 
{
  my ( $self  ) = @_;
  return $self->_error('base class not meant for instantiation');
}

=head2 get_auth_url()

	Retrieve the URL the user must go to to authenticate this app to one or more tenants.

This URL will not be visited automatically by this module. The person who is going to authorise this code to connect to a Xero tenant using their Xero crendentials needs to visit this link in a graphical web browser and carry out the authorisation process. See L<WebService::Xero::Agent::PublicApplication> for full information.

=cut

sub get_auth_url
{
	my ( $self  ) = @_;
	return $self->{_oauth}->authorize()->as_string();	# sic
}

=head2 get_access_token($grant_code)

	Exchange the grant code received by your web app for a longer-lived access token
	
Once you have authorised this app to a Xero tenant, Xero will call your auth_code_url with parameters like this:
  	?code=8877146d9aaebf16e84566edb9416ab9d9626a15e926fe389ba6dfbbdc34b98c&scope=openid%20profile%20email%20accounting.transactions%20accounting.attachments%20accounting.settings%20accounting.contacts%20offline_access&session_state=NaP2bbCmnUkXNn_5fdZPHMU1QQanRzl3G_Ew-IIF5Ik.84f54ec9f443c0e34d25b3be0157a50f_uri
	
Extract that code parameter and then provide it to this method to have us exchange that very short-lived grant code for an access token we can actually use to get to the API. Lives if retrieving an access token was successful, dies if not. The token will be stored in the internal cache, and used for sbusequent calls. 

=cut

sub get_access_token
{
	my $self = shift;
	my $grant_code = shift;
	
	unless($grant_code)
	{
		return $self->_error("Grant code not provided");
	}
	$self->{_cache}->{grant_code} = $grant_code;
	# Save the access token in the cache in thawed format for immediate use
	$self->{_cache}->{access_token} = $self->{_oauth}->get_access_token($grant_code, 
												(grant_type => 'authorization_code', redirect_uri => $self->{AUTH_CODE_URL}));
	return $self->{_cache}->{access_token};
}

sub DESTROY
{
	my $self = shift;
	
	if($self->{_cache}->{access_token})
	{
		$self->{_cache}->{access_token} = $self->{_cache}->{access_token}->session_freeze();	# Save the access token in the cache in frozen format for storage
		unless(store $self->{_cache}, $self->{CACHE_FILE})					# Save the cache
		{	# Write was attempted and went wrong somehow
			return $self->_error("Couldn't write to cache file: $@");
		}
	}
}

=head2 get_all_xero_products_from_xero()

  Experimental: a shortcut to do_xero_api_call

=cut
#####################################
sub get_all_xero_products_from_xero
{
  my ( $self ) = @_;
  #my $data = $self->_do_xero_get( q{https://api.xero.com/api.xro/2.0/Items} );
  my $data = $self->do_xero_api_call( q{https://api.xero.com/api.xro/2.0/Items} ) || return $self->_error('get_all_xero_products_from_xero() failed');
  return $data;
}
#####################################


=head2 get_all_customer_invoices_from_xero()

    Experimental: a shortcut to do_xero_api_call

=cut 

#####################################
sub get_all_customer_invoices_from_xero
{
  my ( $self, $xero_cref ) = @_;  
  my $ret = [];
  my $ext = uri_encode(qq{Contact.ContactID = Guid("$xero_cref")});
  my $page = 1; my $page_count=100;
  while ( $page_count >= 100 and my $data = $self->do_xero_api_call( qq{https://api.xero.com/api.xro/2.0/Invoices?where=$ext&page=$page} ) ) ## continue querying until we have a non-full page ( ie $page_count < 100 )
  {
    foreach my $inv ( @{ $data->{Invoices}{Invoice}} )
    {
      push @$ret, $inv;
      $page_count--;
    }
    if ($page_count  == 0)
    {
      $page_count=100; $page++;
    }
  }
  $self->{status} = 'OK get_all_customer_invoices_from_xero()';
  return $ret;
}
#####################################

=head2 do_xero_api_call()

  INPUT PARAMETERS AS A LIST ( NOT NAMED )

* $uri (required)    - the API endpoint URI ( eg 'https://api.xero.com/api.xro/2.0/Contacts/')
* $method (optional) - 'POST' or 'GET' .. PUT is experimental
* $xml (optional)    - the payload for POST updates as XML

  RETURNS

    The response is requested in JSON format which is then processed into a Perl structure that
    is returned to the caller.
    TODO: handle http response codes as per https://developer.xero.com/documentation/api/http-response-codes


=cut 


sub do_xero_api_call
{
  my ( $self, $uri, $method, $content ) = @_;
  $method = 'GET' unless $method;

  return $self->_error('RETRIEVE AN ACCESS TOKEN FIRST') unless $self->{_cache}->{access_token}->access_token();
  return $self->_error('NO TENANT ID SET') unless $self->{TENANT_ID} || $uri eq "https://api.xero.com/connections";

  my $data = undef;
  my $req = HTTP::Request->new( $method,  $uri );
  $req->header('Authorization' => "Bearer ".$self->{_cache}->{access_token}->access_token());
  $req->header('Xero-Tenant-Id' => $self->{TENANT_ID});
  
  if ( $method eq 'POST' || $method eq 'PUT')
  {
    $req->header( 'Content-Type' => 'application/x-www-form-urlencoded; charset=utf-8' );
    $req->header( 'Accept' => 'application/json' );
	if(openhandle($content))
	{	# We have been passed a file handle
		my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime,
				$mtime, $ctime, $blksize, $blocks) = stat($content);
		my $max_file_size = "10485760"; 								# Max 10Mb according to the files API Documentation
		return $self->_error('FILE TOO LARGE; only files 10Mb or less supported by Xero API') if $size > $max_file_size;
		binmode $content;												# Make sure we are reading bytes
		my $data; read $content, $data, $size;							# Slurp the whole file at once
		$req->content( $data );											# Place in content of body
																		# Something somewhere else seems to be magically setting the Content-Type header so we don't need to
	}
	else
	{
		$req->content( $content ) if defined $content;
	}
  }
  elsif ( $method eq 'GET' )
  {
    #~ {
      #~ $req->header( 'Accept' => 'application/json');
    #~ }
  } 
  else 
  {
    return $self->_error('ONLY POST,PUT AND GET CURRENT SUPPORTED BY WebService::Xero Library');
  }
  my $res = $self->{ua}->request($req);
  if ($res->is_success)
  {
    $self->{status} = 'GOT RESPONSE FROM XERO API CALL';
    if ( $res->header('Content-Type') =~ qr/application\/json/ )
    {
		$data = from_json($res->content) || return $self->api_error( $res->content );  
    }
    elsif($uri =~ qr/Attachments\/(.*)/)
    {	# Content probably an attachment being retrieved, stick it in a temp file and pass back the name.
		# We can't really tell what will be appropriate for the user in terms of how it is read and when
		# destroying it will be appropriate
		my $bytes = $res->content || return $self->api_error( $res->content );
		open FILE, ">", "/tmp/$1" or return $self->_error("COULDN'T OPEN /tmp/$1 FOR WRITING");
		binmode FILE;
		print FILE $bytes;
		close FILE;
		$data = "/tmp/$1";
    }
  }
  else 
  {
    return $self->api_error($res->content);
  }
  return $data, ;
}


=head2 api_error

    Experimental: place to catch known API errors - TODO

=cut 
sub api_error
{
  my ( $self, $msg ) = @_;
  #return $self->_error("SERVER ERROR: CLIENT_ID was not recognised - check your credentials") if ( $msg eq 'oauth_problem=client_id_unknown&oauth_problem_advice=Consumer%20key%20was%20not%20recognised');
  return $self->_error("UNRECOGNISED API ERROR '$msg'");
}



=head2 api_account_organisation()
  
  Experimental: a shortcut to dp_xero_api_call that returns 
  a WebService::Xero::Organisation object describing the organisation that provides the API.

=cut 

sub api_account_organisation
{
  my ( $self ) = @_;
  return WebService::Xero::Organisation->new_from_api_data( $self->do_xero_api_call( 'https://api.xero.com/api.xro/2.0/organisation' ) ) || $self->_error('FAILED TO CREATE ORGANISATION OBJECT FROM AGENT');
}


sub _error 
{
  my ( $self, $msg ) = @_;
  croak($self->{_status} = $msg);
  #$self->{_ERROR_VAL}; ##undef
  return undef;
}


=head2 as_text

  just a quick debugging method.

=cut 

sub as_text
{
  my ( $self ) = @_;
  return qq{    NAME              => $self->{NAME}\nCLIENT_ID      => $self->{CLIENT_ID}\nCLIENT_SECRET   => $self->{CLIENT_SECRET} \n};
}

=head2 get_status

  return a text description of the last communication with the Xero API

=cut 

sub get_status
{
  my ( $self ) = @_;
  return $self->{_status} || 'STATUS NOT SET';
}


=head1 AUTHORS

Peter Scott, C<< <peter at computerpros.com.au> >>; Ian Gibbs C<<igibbs@cpan.org>>

=head1 BUGS

Please report any bugs or feature requests to C<bug-ccp-xero at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CCP-Xero>.  I will be notified, and then you'll
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
