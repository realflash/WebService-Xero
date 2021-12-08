#!perl -T
use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More 0.98;
use Crypt::OpenSSL::RSA;
use File::Slurp;
use URI::Encode qw(uri_encode uri_decode );

use Config::Tiny;

BEGIN {
	use_ok( 'WebService::Xero::Agent::PublicApplication' ) || print "Bail out!\n";

	# as_text
	is( WebService::Xero::Agent::PublicApplication->new() , undef, "attempt to create with invalid parameters failed as expected");

	my $fake_key = '-----BEGIN RSA PRIVATE KEY-----
MIICXQIBAAKBgQCu2PMZrIHPiFmZujY0s7dz8atk1TofVSTVqhWg5h/fn8tYbwgg
koTqpAigxAUCAZ63prtj9LQhIqe3TRNtCDMsxxriyN3O/cxkVD52LwCKAgEoaNmr
Vvt97UgxglKyQ6taNO/c6V8FCKvPC945GKd/b7BoIYZcJsrpo+E+8Ek9IQIDAQAB
AoGAbbPC+0XIAI0dIp256uEjZkSn89Dw8b27Ka/YeCZKs0UQEYFAiSdE6+9VVoEG
X1bi3XloM3PSHMQglJpwaMVvTUwZfdxCFIM0mpgXtdK8Xuh3QTZpgH9S0a2HoXrB
uXFEqvwMcT43ig2FCfVQU86RQZAxrb1YfyFSauEayrVtbT0CQQDe8HEXSkbxjUwj
I2TdCDA7yOW7rWQPAk3REZ33SqBUdo45qofpkH7vWSx+W6q65uyRYfF4N1JKmW8V
OhMxBpFPAkEAyMbGZ2VX6gW37g03OGSoUG6mvXe+CKRqv8hV4UoGeQIUYJTFlt2O
ukD2jKyHqWIdU/3tM3iP1b8CY6JyVyhOjwJBAJ/NmDMKohnJn9bcKxOpJ/HiypIh
8sQzcZY4W5QEYTLKHJ7HV08brXFh6VvV12bL2q1HmLAEb69bll2P2Gve+k8CQQC3
1Pi4lxwl1FKSjlsvMUrDSm01Mbw34YM0UlP/0W2XwoWx4MYB2p7ifrTAHQCh4IoF
64wSAqOADEI9w/F5SBiVAkBJVt3jNObeieMfxVU/NOtajXX51sDUj3XCIWPPui8i
IKzzVn7G0kH+/TqtTPdizrDJkg/rsnrTpvHi8eeMZlAy
-----END RSA PRIVATE KEY-----';

	## test a valid although unusable configuration
	ok( my $xero = WebService::Xero::Agent::PublicApplication->new( CONSUMER_KEY	=> 'CKCKCKCKCKCKCKCKCKCKCKCKCKCKCKCKCKCKCK', 
														  CONSUMER_SECRET => 'CSCSCSCSCSCSCSCSCSCSCSCSCSCSCSCSCSCSCS', 
														  #KEYFILE		 => "/Users/peter/gc-drivers/conf/xero_private_key.pem"
														  PRIVATE_KEY => $fake_key, ) ,  'New Xero Private Application Agent' );
	is( ref($xero), 'WebService::Xero::Agent::PublicApplication', 'created Xero object is the right type' );

	like ( $xero->as_text(), qr/WebService::Xero::Agent::PublicApplication/, 'as_text()' );

	is( $xero->get_all_xero_products_from_xero(), undef, "attempt to get from xero fails with invalid credentials" );

	SKIP: {
		skip ("no config found in ./t/config/test_config.ini - skipping agent tests") unless -e './t/config/test_config.ini' ;
		note(" --- Full Agent tests - loading config ./t/config/test_config.ini");

		## VALIDATE CONFIGURATION FILE
		ok( my $config =  Config::Tiny->read( './t/config/test_config.ini' ) , 'Load Config defined at ./t/config/test_config.ini }' );

		TODO: {
			todo_skip('not implemented',1);
			ok(1==2, 'foo');
		}

		## SKIP PUBLIC APPLICATION UNLESS VALID KEY FILE PROVIDED IN CONFIG
		diag(' --- SKIPPING PRIVATE API CONFIG - KEYFILE NOT FOUND') unless (-e $config->{PRIVATE_APPLICATION}{KEYFILE} );
		SKIP: {
			skip("no Private API config") unless (-e $config->{PRIVATE_APPLICATION}{KEYFILE} );
			#ok( $config->{PUBLIC_APPLICATION}{CONSUMER_KEY} ne 'YOUR_OAUTH_CONSUMER_KEY', 'Private API Consumer key not left as default' );
			ok ( my $pk_text = read_file( $config->{PRIVATE_APPLICATION}{KEYFILE} ), 'load private key file');
			ok ( my $pko = Crypt::OpenSSL::RSA->new_private_key( $pk_text ), 'Generate RSA Object from private key file' );
			ok ( my $xero = WebService::Xero::Agent::PublicApplication->new( 
													  NAME			=> $config->{PRIVATE_APPLICATION}{NAME},
													  CONSUMER_KEY	=> $config->{PRIVATE_APPLICATION}{CONSUMER_KEY}, 
													  CONSUMER_SECRET => $config->{PRIVATE_APPLICATION}{CONSUMER_SECRET}, 
													 # KEYFILE		 => $config->{PRIVATE_APPLICATION}{KEYFILE},
													  PRIVATE_KEY	 => $pk_text,
													  ), 'New Xero Private Application Agent' );
			note( $xero->as_text() );

			## TEST GET PRODUCTS
			ok( my $products = $xero->get_all_xero_products_from_xero(), 'Get live products' );
			note( Dumper $products );

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
}

done_testing;
