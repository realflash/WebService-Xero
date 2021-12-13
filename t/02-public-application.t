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

my $xero;
Log::Log4perl->easy_init($DEBUG);

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
																	CACHE_FILE => "/tmp/WebServiceXero.cache",
																	AUTH_CODE_URL => "http://127.0.0.1:3000"); },
																	qr/No client ID specified/, "Handled no client ID") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => undef,
																	CACHE_FILE => "/tmp/WebServiceXero.cache",
																	AUTH_CODE_URL => "http://127.0.0.1:3000"); },
																	qr/No client secret specified/, "Handled no client secret") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => undef,
																	AUTH_CODE_URL => "http://127.0.0.1:3000"); },
																	qr/No cache file specified/, "Handled no cache file") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => "/tmp/WebServiceXero.cache",
																	AUTH_CODE_URL => undef); },
																	qr/No auth code URL specified/, "Handled no auth code URL") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => "/tmp/WebServiceXero.cache",
																	AUTH_CODE_URL => "http://127.0.0.1:3000"); },
																	qr/Client ID too short/, "Handled short client ID") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2Vhqr",
																	CACHE_FILE => "/tmp/WebServiceXero.cache",
																	AUTH_CODE_URL => "http://127.0.0.1:3000"); },
																	qr/Client secret too short/, "Handled short client secret") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => "/tmp/WebServiceXero.cache",
																	AUTH_CODE_URL => "notaURL"); },
																	qr/not a valid HTTP or HTTPS URL/, "Auth code URL is not a valid URL") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => "/79347293474897/WebServiceXero.cache",
																	AUTH_CODE_URL => "http://127.0.0.1:3000"); },
																	qr/doesn't exist and is not writeable/, "Non-existent cache file is not writeable") or note($@);
# Create cache file for testing
my $tmp = File::Temp->new( TEMPLATE => 'WebService::Xero_test_XXXXX',
					   DIR => '/tmp',
					   SUFFIX => '.cache');
SKIP: {
	skip(" writeability tests as they only work on (Li|u)nix when not root") unless $^O =~ /linux/i && $> != 0;
	
	chmod 0444, $tmp->filename;
	like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																		CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																		CACHE_FILE => $tmp->filename,
																		AUTH_CODE_URL => "http://127.0.0.1:3000"); },
																		qr/cache file exists and is not writeable/, "Existent cache file is not writeable") or note($@);
	chmod 0000, $tmp->filename;
	like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																		CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																		CACHE_FILE => $tmp->filename,
																		AUTH_CODE_URL => "http://127.0.0.1:3000"); },
																		qr/cache file exists and is not readable/, "Existent cache file is not readable") or note($@);
	chmod 0666, $tmp->filename;
}

# Test a corrupted cache file
print $tmp "LOADOFOLDCOBBLERS";
close $tmp;
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => $tmp->filename,
																	AUTH_CODE_URL => "http://127.0.0.1:3000"); },
																	qr/corrupt/, "Corrupted cache file is detected") or note($@);

## Test a valid although unusable configuration
try_ok {$xero = WebService::Xero::Agent::PublicApplication->new( CLIENT_ID	=> '7CA8F60E5C7D479CA71EB7958F0B16A8', 
																	CLIENT_SECRET => 'uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP',
																	CACHE_FILE => "/tmp/WebServiceXero.cache",
																	AUTH_CODE_URL => "https://127.0.0.1:3000")} "Correct parameters don't throw exception, HTTPS";
try_ok {$xero = WebService::Xero::Agent::PublicApplication->new( CLIENT_ID	=> '7CA8F60E5C7D479CA71EB7958F0B16A8', 
																	CLIENT_SECRET => 'uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP',
																	CACHE_FILE => "/tmp/WebServiceXero.cache",
																	AUTH_CODE_URL => "http://127.0.0.1:3000")} "Correct parameters don't throw exception, HTTP";
is( ref($xero), 'WebService::Xero::Agent::PublicApplication', 'created Xero object is the right type' );

SKIP: {
	skip ("active agent tests; no config found in ./t/config/test_config.ini") unless -e './t/config/test_config.ini' ;
	note(" --- Running authentication tests - loading config ./t/config/test_config.ini");

	## VALIDATE CONFIGURATION FILE
	ok( my $config =  Config::Tiny->read( './t/config/test_config.ini' ) , 'Load Config defined at ./t/config/test_config.ini }' );
	ok(defined($config->{'PUBLIC_APPLICATION'}->{'CLIENT_ID'}), "Config file has an ID in it");
	ok(defined($config->{'PUBLIC_APPLICATION'}->{'CLIENT_SECRET'}), "Config file hs a secret in it");

	## Initialise with config file
	try_ok {$xero = WebService::Xero::Agent::PublicApplication->new( 
													NAME			=> $config->{'PUBLIC_APPLICATION'}->{'NAME'},
													CLIENT_ID	=> $config->{'PUBLIC_APPLICATION'}->{'CLIENT_ID'}, 
													CLIENT_SECRET => $config->{'PUBLIC_APPLICATION'}->{'CLIENT_SECRET'},
													CACHE_FILE => "/tmp/WebServiceXero.cache",
													AUTH_CODE_URL => $config->{'PUBLIC_APPLICATION'}->{'AUTH_CODE_URL'},
											  )} "Agent object initialises with correct parameters";
											  
	## Get a auth URL for the user to visit
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
	
	
	
	
	#~ note("Auth URL is $auth_url");
	
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
