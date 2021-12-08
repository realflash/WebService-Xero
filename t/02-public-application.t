#!perl -T
use 5.006;
use strict;
use warnings;
use Data::Dumper;
use Test::More 0.98;
use Test2::Tools::Exception qw/dies lives/;
use Crypt::OpenSSL::RSA;
use File::Slurp;
use URI::Encode qw(uri_encode uri_decode );

use Config::Tiny;

BEGIN {
	# Test with no parameters
	is( WebService::Xero::Agent::PublicApplication->new() , undef, "attempt to create with invalid parameters failed as expected");

	## Test a valid although unusable configuration
	my $xero;
	ok(lives {$xero = WebService::Xero::Agent::PublicApplication->new( CLIENT_ID	=> '7CA8F60E5C7D479CA71EB7958F0B16A8', 
														  CLIENT_SECRET => 'uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP')}, "Correct parameters don't throw exception" );
	is( ref($xero), 'WebService::Xero::Agent::PublicApplication', 'created Xero object is the right type' );

	like ( $xero->as_text(), qr/WebService::Xero::Agent::PublicApplication/, 'as_text()' );

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
