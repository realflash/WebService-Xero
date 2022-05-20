#
#
# CREATE A COPY OF THIS FILE AND STORE THE LOCATION IN 
# THE ENVIRONMENT VARIABLE XERO_TEST_CONFIG TO ENABLE
# WHEN PERFORMING A 'make test'
#
# by default test will try to load t/config/test_config.ini
# THIS ENV WILL ALSO WORK FOR COMMAND LINE WHERE VALUES
# ARE NOT PASSED INTO THE CONSTRUCTOR
#
# See README and 'perldoc WebService::Xero' for more detail
#

[PUBLIC_APPLICATION]
NAME			= 
CLIENT_ID		= 
CLIENT_SECRET	=
Data::Validate::URI
# This URL has to be registered on developer.xero.com before it works!
AUTH_CODE_URL	= http://localhost:3000/auth
