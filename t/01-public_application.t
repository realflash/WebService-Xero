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
																	REDIRECT_URI => undef); },
																	qr/No client ID specified/, "Handled no client creds at all 2") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => undef,
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => $cache_file,
																	REDIRECT_URI => $callback_url); },
																	qr/No client ID specified/, "Handled no client ID") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => undef,
																	CACHE_FILE => $cache_file,
																	REDIRECT_URI => $callback_url); },
																	qr/No client secret specified/, "Handled no client secret") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => undef,
																	REDIRECT_URI => $callback_url); },
																	qr/No cache file specified/, "Handled no cache file") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => $cache_file,
																	REDIRECT_URI => undef); },
																	qr/No auth code URL specified/, "Handled no auth code URL") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => $cache_file,
																	REDIRECT_URI => $callback_url); },
																	qr/Client ID too short/, "Handled short client ID") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2Vhqr",
																	CACHE_FILE => $cache_file,
																	REDIRECT_URI => $callback_url); },
																	qr/Client secret too short/, "Handled short client secret") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => $cache_file,
																	REDIRECT_URI => "notaURL"); },
																	qr/not a valid HTTP or HTTPS URL/, "Auth code URL is not a valid URL") or note($@);
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => "/79347293474897/WebServiceXero.cache",
																	REDIRECT_URI => $callback_url); },
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
																		REDIRECT_URI => $callback_url); },
																		qr/cache file exists and is not writeable/, "Existent cache file is not writeable") or note($@);
	chmod 0000, $tmp->filename;											# Make file neither readable nor writeable
	like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																		CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																		CACHE_FILE => $tmp->filename,
																		REDIRECT_URI => $callback_url); },
																		qr/cache file exists and is not readable/, "Existent cache file is not readable") or note($@);
	chmod 0666, $tmp->filename;											# Make file readable and writeable again
}

# Test a corrupted cache file
print $tmp "LOADOFOLDCOBBLERS";
close $tmp;
like(dies { $xero = WebService::Xero::Agent::PublicApplication->new(CLIENT_ID => "7CA8F60E5C7D479CA71EB7958F0B16A8",
																	CLIENT_SECRET => "uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP",
																	CACHE_FILE => $tmp->filename,
																	REDIRECT_URI => $callback_url); },
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
																	REDIRECT_URI => "https://localhost:3000/auth")} "Correct parameters don't throw exception, HTTPS; also valid cache file reading";
try_ok {$xero = WebService::Xero::Agent::PublicApplication->new( CLIENT_ID	=> '7CA8F60E5C7D479CA71EB7958F0B16A8', 
																	CLIENT_SECRET => 'uIHcAADccDLmbrBo-WrbxTgwjaUAzxMbp897EOac2Q2VhqrP',
																	CACHE_FILE => $cache_file,
																	REDIRECT_URI => $callback_url)} "Correct parameters don't throw exception, HTTP; also valid cache file reading";
is( ref($xero), 'WebService::Xero::Agent::PublicApplication', 'created Xero object is the right type' );

done_testing;
