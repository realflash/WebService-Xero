#!/usr/bin/perl

use strict;
use warnings;
use Test::HTTP::MockServer::Once;
use Async;
use Storable qw(thaw);
use WebService::Xero::Agent::PublicApplication;
use URI::QueryParam;
use Data::Dump qw(dump);

my $server = Test::HTTP::MockServer::Once->new(port => 3000);			# Opens http://localhost:3000
my $handle_request = sub {												# Responds to /anything
	my ($request, $response) = @_;
	$response->content("OK");											# User's browser doesn't care what it gets back.
};
my $proc = AsyncTimeout->new(sub { $server->start_mock_server($handle_request) }, 300, "TIMEOUT");

print "Web server running ready to receive authorisation grant from Xero. Go to this link below to authorise this testing code to access a Xero tenant, using THIS COMPUTER. I'll wait up to five minutes for you.\n";

my $xero = WebService::Xero::Agent::PublicApplication->new( 
												CLIENT_ID	=> <your-client-id>, 										# Get this from Xero when registering
												CLIENT_SECRET => <your-client-secret>,									# Get this from Xero when registering
												CACHE_FILE => "/path/to/secure/file/storing/creds/for/this/user",		# Per user
												REDIRECT_URI => "http://localhost:3000/callback",						# Must match what you registered with Xero
										  );
print $xero->get_auth_url()."\n";

# Wait until the request comes in or it times out
my $result = $proc->result('force completion');                                               
die "Timed out waiting for authorisation grant code received from Xero. Did you follow the link on this computer or somewhere else?" if $proc->result eq "TIMEOUT";

# Got a response
my $interaction = thaw $result;
my $called_uri = $interaction->{request}->uri;
die "Error returned by Xero: ".$called_uri->query_param('error') if $called_uri->query_param('error');
die "Authorisation grant doesn't contain a grant code" unless $called_uri->query_param('code');

# Get an access token and store it in the cache file
$xero->get_access_token($called_uri->query_param('code'));

# Find out tenant IDs
dump($xero->do_xero_api_call("https://api.xero.com/connections"));
