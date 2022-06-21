#!perl -T
use 5.006;
use strict;
use warnings;
use Data::Dump qw(dump);
use Test::More 0.98;
use Test2::Tools::Exception qw/dies lives try_ok/;
use File::Slurp;
use URI::Encode qw(uri_encode uri_decode );
use WebService::Xero::Agent::PublicApplication;
use Config::Tiny;
use Log::Log4perl qw(:easy);
use URI;
use URI::QueryParam;
use Data::Validate::URI qw(is_uri is_https_uri is_web_uri);
use File::Temp qw(tempfile);
use Test::HTTP::MockServer::Once;
use Async;
use Storable qw(thaw);
use DateTime;
use FindBin qw($RealBin);
use Digest::MD5;
use File::stat;

my $xero;
Log::Log4perl->easy_init($TRACE);
my $cache_file = $ENV{"HOME"}.'/.WebServiceXero.cache';					# It's tempting to make this a /tmp file but in order to test re-authorisation after a few days you don't
																		# the file disappearing in a reboot.
my $callback_url = 'http://localhost:3000/auth';						# WARNING: the Xero OAuth service requires a fragment in the URL, and localhost. The fragment can be anything,
																		# it just can't be empty. So http://127.0.0.1:3000 doesn't work - the Xero firewall deems it some
																		# kind of remote file inclusion attack and blocks it, returning an HTTP 403. http://localhost:3000/something
																		# does work. Our mock server Test::HTTP::MockServer::Once does not care about fragments, it returns 
																		# the same content no matter the fragment, so that's fine.
																		# This particular value is not used in anger, so it doesn't matter if it does or doesn't match what's
																		# in the test config
																			
# Test bad parameters
# Client ID should be 32 chars long. There's no credential format standardisation in the protocol so this could change in future but it will help confirm the user hasn't accidentially failed to copy the whole thing
# Client secret should be 48 chars long
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(); }, qr/No client ID specified/, "Handled no client creds at all 1") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => undef, 
																	CLIENT_SECRET => undef, 
																	CACHE_FILE => undef, 
																	AUTH_CODE_URL => undef); },
																	qr/No client ID specified/, "Handled no client creds at all 2") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => undef,
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => $cache_file,
																	AUTH_CODE_URL => $callback_url); },
																	qr/No client ID specified/, "Handled no client ID") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => undef,
																	CACHE_FILE => $cache_file,
																	AUTH_CODE_URL => $callback_url); },
																	qr/No client secret specified/, "Handled no client secret") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => undef,
																	AUTH_CODE_URL => $callback_url); },
																	qr/No cache file specified/, "Handled no cache file") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => $cache_file,
																	AUTH_CODE_URL => undef); },
																	qr/No auth code URL specified/, "Handled no auth code URL") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => $cache_file,
																	AUTH_CODE_URL => $callback_url); },
																	qr/Client ID too short/, "Handled short client ID") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2Vhqr",
																	CACHE_FILE => $cache_file,
																	AUTH_CODE_URL => $callback_url); },
																	qr/Client secret too short/, "Handled short client secret") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => $cache_file,
																	AUTH_CODE_URL => "notaURL"); },
																	qr/not a valid HTTP or HTTPS URL/, "Auth code URL is not a valid URL") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => "/79347293474897/WebServiceXero.cache",
																	AUTH_CODE_URL => $callback_url); },
																	qr/No such file or directory/, "Non-existent cache file is not writeable") or note($@);
# Create cache file for testing
my $tmp = File::Temp->new( TEMPLATE => 'WebService::Xero_test_XXXXX',
					   DIR => '/tmp',
					   SUFFIX => '.cache');
SKIP: {
	skip(" writeability tests as they only work on (Li|u)nix when not root") unless $^O =~ /linux/i && $> != 0;
	
	chmod 0444, $tmp->filename;											# Make file not writeable
	like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																		CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																		CACHE_FILE => $tmp->filename,
																		AUTH_CODE_URL => $callback_url); },
																		qr/cache file exists and is not writeable/, "Existent cache file is not writeable") or note($@);
	chmod 0000, $tmp->filename;											# Make file neither readable nor writeable
	like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																		CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																		CACHE_FILE => $tmp->filename,
																		AUTH_CODE_URL => $callback_url); },
																		qr/cache file exists and is not readable/, "Existent cache file is not readable") or note($@);
	chmod 0666, $tmp->filename;											# Make file readable and writeable again
}

# Test a corrupted cache file
print $tmp "LOADOFOLDCOBBLERS";
close $tmp;
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => $tmp->filename,
																	AUTH_CODE_URL => $callback_url); },
																	qr/Couldn't/, "Corrupted cache file is detected") or note($@);
unlink($tmp->filename); 												# Can leave rubbish lying around if tests fail

# Untaint this variable so Storable doesn't bitch
if ($cache_file =~ /^([-_\w\.\/]+)$/)
{
	$cache_file = $1;
}
else
{
	die 'Bad data in $cache_file variable';
}

## Test a valid although unusable configuration
try_ok {$xero = WebService::Xero::Agent::PublicApplication->new( CLIENT_ID	=> '7CA8F60E5C7D479CA71EB7958F0B16A8', 
																	CLIENT_SECRET => 'uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP',
																	CACHE_FILE => $cache_file,
																	AUTH_CODE_URL => "https://localhost:3000/auth")} "Correct parameters don't throw exception, HTTPS; also valid cache file reading";
try_ok {$xero = WebService::Xero::Agent::PublicApplication->new( CLIENT_ID	=> '7CA8F60E5C7D479CA71EB7958F0B16A8', 
																	CLIENT_SECRET => 'uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP',
																	CACHE_FILE => $cache_file,
																	AUTH_CODE_URL => $callback_url)} "Correct parameters don't throw exception, HTTP; also valid cache file reading";
is( ref($xero), 'WebService::Xero::Agent::PublicApplication', 'created Xero object is the right type' );

SKIP: {
	skip ("active agent tests; no config found in ./t/config/test_config.ini") unless -e './t/config/test_config.ini' ;
	note(" --- Running authentication tests - loading config ./t/config/test_config.ini");

	## VALIDATE CONFIGURATION FILE
	ok( my $config =  Config::Tiny->read( './t/config/test_config.ini' ) , 'Load Config defined at ./t/config/test_config.ini }' );
	ok(defined($config->{'PUBLIC_APPLICATION'}->{'NAME'}), "Config file has an name in it");				# Has to be globally unique so we can't default it
	ok(defined($config->{'PUBLIC_APPLICATION'}->{'CLIENT_ID'}), "Config file has an ID in it");				# Has to be obtained by registering the app
	ok(defined($config->{'PUBLIC_APPLICATION'}->{'CLIENT_SECRET'}), "Config file has a secret in it");		# Has to be obtained by registering the app
	ok(defined($config->{'PUBLIC_APPLICATION'}->{'TEST_TENANT_ID'}), "Config file has a testing tenant");	# Has to chosen carefully and user has to join it

	my $test_tenant_id = $config->{'PUBLIC_APPLICATION'}->{'TEST_TENANT_ID'};	# These potentially destructive tests (including creating and deleting data) will be carried out 
																				# in this tenant. There is a demo company in Xero that anyone can join and mess about with. It's called
																				# "Demo Company (UK)". It gets reset sometimes, and the tenant ID changes so this test config will need
																				# to be updated and this library re-connected.
	# Initialise with config file
	try_ok {$xero = WebService::Xero::Agent::PublicApplication->new( 
													NAME			=> $config->{'PUBLIC_APPLICATION'}->{'NAME'},
													CLIENT_ID	=> $config->{'PUBLIC_APPLICATION'}->{'CLIENT_ID'}, 
													CLIENT_SECRET => $config->{'PUBLIC_APPLICATION'}->{'CLIENT_SECRET'},
													CACHE_FILE => $cache_file,
													AUTH_CODE_URL => $config->{'PUBLIC_APPLICATION'}->{'AUTH_CODE_URL'},
											  )} "Agent object initialises with correct parameters";
											  
	# Get an auth URL for the user to visit
	my $auth_url;
	try_ok {$auth_url = $xero->get_auth_url();} "Authorisation URL method doesn't crash";
	ok(defined($auth_url), "Auth URL is not undefined");
	ok(is_uri($auth_url), "Auth URL is a valid URI");
	ok(is_https_uri($auth_url), "Auth URL scheme is HTTPS");
	my $auth_uri = URI->new($auth_url);
	is($auth_uri->query_param('redirect_uri'), $config->{'PUBLIC_APPLICATION'}->{'AUTH_CODE_URL'}, "redirect_uri is correctly defined");
	is($auth_uri->query_param('client_id'), $config->{'PUBLIC_APPLICATION'}->{'CLIENT_ID'}, "client_id is correctly defined");
	is($auth_uri->query_param('response_type'), "code", "response_type is correctly defined");
	is($auth_uri->query_param('scope'), "openid profile email accounting.transactions accounting.attachments accounting.settings accounting.contacts offline_access", "scope is correctly defined");
	
	# Get an access token
	my $server_uri = URI->new($config->{'PUBLIC_APPLICATION'}->{'AUTH_CODE_URL'});
	try_ok {$xero = WebService::Xero::Agent::PublicApplication->new( 
												NAME			=> $config->{'PUBLIC_APPLICATION'}->{'NAME'},
												CLIENT_ID	=> $config->{'PUBLIC_APPLICATION'}->{'CLIENT_ID'}, 
												CLIENT_SECRET => $config->{'PUBLIC_APPLICATION'}->{'CLIENT_SECRET'},
												CACHE_FILE => $cache_file,
												AUTH_CODE_URL => $server_uri->as_string,
										  )} "Agent object initialises with temp web server URI";

	if($xero->{_cache}->{access_token})
	{
		note("Found an existing access token. Attempting to use it. Refresh occurs automatically if possible.");
	}
	else
	{
		note("No existing access token. Starting temp web server for authorisation grant");
		my $server = Test::HTTP::MockServer::Once->new(port => $server_uri->port);
		my $handle_request = sub {
			my ($request, $response) = @_;
			$response->content("OK");									# We shouldn't need to do anything here apart from give back something sensible to Xero
		};
		my $proc = AsyncTimeout->new(sub { $server->start_mock_server($handle_request) }, 300, "TIMEOUT");
		note("Web server running ready to receive authorisation grant from Xero. Go to this link below to authorise this testing code to access a Xero tenant, using THIS COMPUTER. I'll wait up to five minutes for you.");
		note($xero->get_auth_url());

		# Wait until the request comes in or it times out
		my $result = $proc->result('force completion');                                               
		BAIL_OUT("Timed out waiting for authorisation grant code received from Xero. Did you follow the link on this computer or somewhere else?") if($proc->result eq "TIMEOUT");
		my $interaction = thaw $result;
		my $called_uri = $interaction->{request}->uri;
		BAIL_OUT("Error returned by Xero: ".$called_uri->query_param('error')) if $called_uri->query_param('error');
		BAIL_OUT("Authorisation grant doesn't contain a grant code") unless $called_uri->query_param('code');

		# Get an spanky new access token
		my $access_token;
		like(dies { $xero->get_access_token() }, qr/Grant code not provided/, "Handled no grant code provided") or note($@);
		try_ok {$access_token = $xero->get_access_token($called_uri->query_param('code'))} "Got access token from grant code";
		ok(defined($xero->{_cache}->{access_token}), "Access token is stored");
		is($xero->{_cache}->{access_token}->auto_refresh, 1, "Access token auto refresh is on");
	}

	my $expiry_time = DateTime->from_epoch(epoch => $xero->{_cache}->{access_token}->expires_at());
	note("Access token expires at ".$expiry_time->iso8601()."Z");
	
	# Check that the access token is still valid for at least one tenant
	# GET
	my $tenants;
	try_ok { $tenants = $xero->do_xero_api_call("https://api.xero.com/connections") } "Got tenant list successfully";
	is(ref($tenants), "ARRAY", "Method has returned an object and not an error string");
	ok(scalar(@$tenants) > 0, "At least one tenant is authorised so that we can continue testing");
	# Check if the tenant intended for testing is included in the list
	my $testing_tenant;
	foreach my $tenant (@$tenants)
	{
		if($tenant->{'tenantId'} eq $test_tenant_id)
		{
			$testing_tenant = $tenant;
		}
		note("You have access to tenant ".$tenant->{'tenantName'}." (".$tenant->{'tenantId'}.")");
	}
	
	SKIP: {
		skip ("You are authorised to access one or more tenants but the tenant configured for testing is not one of them.") unless $testing_tenant;
		note ("Continuing testing; using tenant ".$testing_tenant->{'tenantName'}." (".$testing_tenant->{'tenantId'}.")");
	}

	# Now check that GET, PUT and POST calls against the test tenant all work as expected
	$xero->{'TENANT_ID'} = $testing_tenant->{'tenantId'};
	# PUT a new contact - here's Xero's example:
	#{ "Contacts": [ { "ContactID": "3ff6d40c-af9a-40a3-89ce-3c1556a25591", "ContactStatus": "ACTIVE", "Name": "Foo9987", "EmailAddress": "sid32476@blah.com", "BankAccountDetails": "", "Addresses": [ { "AddressType": "STREET", "City": "", "Region": "", "PostalCode": "", "Country": "" }, { "AddressType": "POBOX", "City": "", "Region": "", "PostalCode": "", "Country": "" } ], "Phones": [ { "PhoneType": "DEFAULT", "PhoneNumber": "", "PhoneAreaCode": "", "PhoneCountryCode": "" }, { "PhoneType": "DDI", "PhoneNumber": "", "PhoneAreaCode": "", "PhoneCountryCode": "" }, { "PhoneType": "FAX", "PhoneNumber": "", "PhoneAreaCode": "", "PhoneCountryCode": "" }, { "PhoneType": "MOBILE", "PhoneNumber": "555-1212", "PhoneAreaCode": "415", "PhoneCountryCode": "" } ], "UpdatedDateUTC": "/Date(1551399321043+0000)/", "ContactGroups": [], "IsSupplier": false, "IsCustomer": false, "SalesTrackingCategories": [], "PurchasesTrackingCategories": [], "PaymentTerms": { "Bills": { "Day": 15, "Type": "OFCURRENTMONTH" }, "Sales": { "Day": 10, "Type": "DAYSAFTERBILLMONTH" } }, "ContactPersons": [] } ] }
	my $random_contact_name = "WSX_".int(rand(1000000));
	my $test_contact_json = '
{
	"Contacts": [
		{
		"Name": "'.$random_contact_name.'",
		}
	]
} 
';
	my $response; 
	note("Access token expires at ".$expiry_time->iso8601()."Z");
	try_ok { $response = $xero->do_xero_api_call("https://api.xero.com/api.xro/2.0/Contacts", "PUT", $test_contact_json) } "PUT a new contact successfully";
	is($response->{'Status'}, "OK", "API reports success");
	my $contact = $response->{'Contacts'}[0];
	my $contact_id = $contact->{'ContactID'};

	# GET a contact
	note("Access token expires at ".$expiry_time->iso8601()."Z");
	try_ok { $response = $xero->do_xero_api_call("https://api.xero.com/api.xro/2.0/Contacts/$contact_id") } "GET the contact";
	is($response->{'Status'}, "OK", "API reports success");
	is($response->{'Contacts'}[0]->{'Name'}, $random_contact_name, "Expected contact was returned");

	# PUT an existing contact
	$test_contact_json = '
{
	"Contacts": [
		{
			"ContactID": "'.$contact_id.'",
			"EmailAddress": "imadethis@up.com",
		}
	]
} 
	';
	# This should return this truly terrible error response:
	#UNRECOGNISED API ERROR '{"Title":"An error occurred","Detail":"An error occurred in Xero. Check the API Status page http://status.developer.xero.com for current service status.","Status":500,"Instance":"b90a8446-13fc-4ea1-b950-7652d8710fda"}'
	like( dies { $response = $xero->do_xero_api_call("https://api.xero.com/api.xro/2.0/Contacts/$contact_id", "PUT", $test_contact_json); }, qr/UNRECOGNISED API ERROR/, "PUT a new contact which conflicts with an existing contact");								
	is($response->{'Status'}, "OK", "API reports success");				# This doesn't seem right, though. If Xero threw an error, we should too

	# Attach a file to something
	my $test_file = "chameleon.jpg";									# 300Kb. Enough to not be trivial.
	my $test_file_path = "$RealBin/chameleon.jpg";
	my $test_file_uri = "https://api.xero.com/api.xro/2.0/Contacts/$contact_id/Attachments/$test_file";
	open(my $fh, "<", $test_file_path) or die "Couldn't open test file $test_file_path";
	binmode $fh;
	try_ok { $response = $xero->do_xero_api_call($test_file_uri, "PUT", $fh); } "Attach a file to a contact";
	close $fh;
	# Download the file again to confirm it got there OK.
	my $downloaded_file_path;
	try_ok { $downloaded_file_path = $xero->do_xero_api_call($test_file_uri, "GET"); } "Attach a file to a contact";
	
	#~ # Check the file we get back is the same as what we uploaded
	open($fh, "<", $test_file_path) or die "Couldn't open test file $test_file_path";
	binmode $fh;
	my $md5 = Digest::MD5->new; $md5->addfile($fh);
	my $test_file_md5 = $md5->hexdigest();
	close $fh;
	open($fh, "<", $downloaded_file_path) or die "Couldn't open downloaded test file $response";
	binmode $fh;
	$md5 = Digest::MD5->new;
	$md5->addfile($fh);
	my $returned_file_md5 = $md5->hexdigest();
	close $fh;
	is($returned_file_md5, $test_file_md5, "File we downloaded is the same as the one we uploaded");

	#~ # POST an update to a contact (archiving the mess we made earlier)
	$test_contact_json = '
{
	"Contacts": [
		{
			"ContactID": "'.$contact_id.'",
			"ContactStatus": "ARCHIVED",
		}
	]
} 
	';
	try_ok { $response = $xero->do_xero_api_call("https://api.xero.com/api.xro/2.0/Contacts", "POST", $test_contact_json) } "POST an update to a contact successfully";
	is($response->{'Status'}, "OK", "API reports success");

	TODO: {
		todo_skip('stuff not re-implemented yet',1);

		## TEST GET PRODUCTS
		ok( my $products = $xero->get_all_xero_products_from_xero(), 'Get live products' );
		note(dump($products));

		## TEST GET ORAGNISATION DETAILS
		ok( my $org = $xero->api_account_organisation(), 'Get API Owner Organisation Details' );
		note( $org->as_text() );

		## TEST SEACH FOR RODNEY ( requires specific Xero instance )
		##   Name.Contains("Peter")
		#ok( my $contact = WebService::Xero::Contact->new_from_api_data(  $xero->do_xero_api_call( q{https://api.xero.com/api.xro/2.0/Contacts?where=Name.Contains("Antique")} ) ) , 'Get Contact Peter');
		#note(  $contact->as_text() );

		## TEST INVOICES
		my $filter = '';# uri_encode(qq{Contact.ContactID=Guid("$contact->{ContactID}")});
		ok( my $invoices = WebService::Xero::Invoice->new_from_api_data(  $xero->do_xero_api_call( qq{https://api.xero.com/api.xro/2.0/Invoices?where=$filter} ) ) , "Get Invoices");
		note(  "Got " . scalar(@$invoices) . " invoices '" );

		## GET PRODUCTS
		#$filter = uri_encode(qq{ItemID=Guid("7f2f877b-0c3d-4004-8693-8fb1c06e21d7")});
		#$filter = uri_encode(qq{Code="SZG8811-CUSTOM"});
		ok( my $items = WebService::Xero::Item->new_from_api_data(  $xero->do_xero_api_call( qq{https://api.xero.com/api.xro/2.0/Items?where=$filter} ) ) , "Get Invoices ");
		my $txt = ''; 
		if ( ref($items) eq 'ARRAY' ) { foreach my $item(@$items) { $txt.=$item->as_text(); }; } else { $txt = $items->as_text(); }
		note( "\n\nFOUND ITEM\n" . $txt );

		## CREATE INVOICE
		#my $new_invoice = WebService::Xero::Invoice->new();

		## GET CUSTOMER INVOICES
		#my $alpha_san_xero_contact_id = '8c7bb386-7eb5-4ee7-a624-eba1e4003844';
		#ok(my $data2 = $xero->get_all_customer_invoices_from_xero( $alpha_san_xero_contact_id ), 'get alphasan invoices' );
		#note(  "Alphasan has " . scalar(@$data2)  . " invoices" );
	}
}

done_testing;
