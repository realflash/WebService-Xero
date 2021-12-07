# WebService::Xero

[![Build Status](https://travis-ci.org/pscott-au/CCP-Xero.svg?branch=master)](https://travis-ci.org/pscott-au/CCP-Xero)
[![Coverage Status](https://coveralls.io/repos/github/pscott-au/CCP-Xero/badge.svg?branch=master)](https://coveralls.io/github/pscott-au/CCP-Xero?branch=master)
[![CPAN Version](https://img.shields.io/cpan/v/WebService-Xero.svg)](http://search.cpan.org/~localshop/WebService-Xero/lib/WebService/Xero.pm)
[![Join the chat at https://gitter.im/CCP-AU/](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/CCP-AU?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badgeP-AU/Lobby?source=orgpage)

Perl CPAN style module to simplify integration with [Xero API Applications](https://developer.xero.com)

Inspired by the Xero endorsed Ruby API Library [Xeroizer] 
and the CPAN [Net::Xero](http://search.cpan.org/~elliott/Net-Xero/lib/Net/Xero.pm) module, this Perl module aims to simplify integration with the Xero API.
WebService::Xero modules primarily encapsulate the [OAuth (v1.0a) access control protocol as described by Cubrid](http://www.cubrid.org/blog/dev-platform/dancing-with-oauth-understanding-how-authorization-works/) .


# Active Development Version 0.13 

* Support for PUT REST commands with examples such for example to create new accounts as per [Xero Docs](https://developer.xero.com/documentation/api/accounts#PUT)
* Supoprt for PDF handling
* More robust coverage of common usage in examples
* Reworking Date handling starting with Invoice class
* Refine overall design and address whether object instances are bound to Xero DB or whether can be created from data stand-alone
* Improve and expand exampels with actual useful snippets
* Improve documentation and include instructions for direct API access without needing the Xero Object classes.



# Install from CPAN

This package is now available through [CPAN](http://search.cpan.org/~localshop/WebService-Xero/)

````sh

  perl -MCPAN -e 'install WebService::Xero'

````

## XML-SAX Dependency

Because of dependencies on native XML libraries by some of the modules dependencies you may need to install native expat / xml libraries.

On AWS Linux you may need to install perl-XML-SAX using the package manager ````sudo yum install perl-XML-SAX perl-XML-Parser````

For other platforms see the [GitHub Wiki](https://github.com/pscott-au/CCP-Xero/wiki/Installation-Dependency-Issues)




# Building from Source

## Prerequisites 

* Perl
* build tools ( make etc )
* Xero API Application with credentials as descibed in the [Xero Developer Getting Started Guide](https://developer.xero.com/documentation/getting-started/getting-started-guide/)

````sh
sudo apt-get install perl build-essential ## eg debian package install
````



## Installing Manually


This Perl code is in the standard CPAN package format and can be installed through CPAN or downloaded and installed manually either from [GitHub](https://github.com/Combined-Computer-Professionals/WebService-Xero) or CPAN:

```sh
  perl Makefile.PL
  make
  make test
  make install
```

### Installing Step by Step

Download the latest stable source:

```sh
    git clone https://github.com/Combined-Computer-Professionals/WebService-Xero
    cd WebService-Xero
```

or Download the bleeding edge development version source:
```sh
    git clone https://github.com/pscott-au/CCP-Xero
    cd CCP-Xero
```

Configure your API credentials:
```sh
    cp t/config/test_config.tpl ./t/config/test_config.ini
    nano ./t/config/test_config.ini
```



Create the makefile

```sh
perl Makefile.PL
```
If given notice of missing dependency modules, these can be installed from CPAN. For example to install a missing Crypt::OpenSSL::RSA module:
```sh
    sudo perl -MCPAN -e "install Crypt::OpenSSL::RSA"
    ## or if you have cpanm installed
    cpanm --installdeps .
```

NB: Crypt::OpenSSL::RSA from CPAN requires SSL devel libraries which
    can be installed as follows:
```sh 
  apt-get install libssl-dev   ## for debian etc
  yum install openssl-devel    ## for RH,Centos, Ubuntu etc
```

Make,test and install the library. Most tests will not be run by default, as setting up a Xero application with OAuth keys etc. is required. For more information on runnning the full set of tests, see the Development section.
```sh
make
make test
make install
```

## Usage

TODO 

## AND THEN ACCESS THE XERO API POINTS

my $contact_struct = $xero->do_xero_api_call( 'https://api.xero.com/api.xro/2.0/Contacts' );
print Dumper $contact_struct; ## should contain an array of hashes containing contact data.
````

An example of a minimalistic Mojolicious framework Public Application implementation can be found at [github.com/pscott-au/mojolicious-xero-public-app-demo](https://github.com/pscott-au/mojolicious-xero-public-app-demo)

There are also a couple of examples within the tests directory t and in the examples folder.


See perldoc for details
````sh
perldoc WebService::Xero
perldoc WebService::Xero::Agent::PublicApplication
perldoc WebService::Xero::Contact
perldoc WebService::Xero::Contacts_Container
````
# Development

## Running the full test suite
To run all of the tests, do the following:

* [Log in to Xero developer](https://developer.xero.com/app/manage), creating an account as necessary
* Click the **New app** button in the top right-hand corner
* Set **Name** to *WebService::Zero* (can't have Zero in the name)
* Set the **Integration type** to **Web app**
* Set the **Company or application URL** to whatever you like
* Set the **Redirect URI** to *http://localhost:8082/callback*
* Click **Create app** at the bottom
* Once the app is created, click **Configuration** on the left-hand side.
* Copy the Client id and set it in TODO
* Click **Generate a secret** and then set it in TODO
* Run ./xero-token-init
* Select **Demo Company (UK)** at the top
* Click **Allow access for 30 minutes** TODO check this is the same when offline is requested.

Tokens are now saved in TODO. 

Set ENV vars if you require verbose testing.
````sh
export   RELEASE_TESTING=1
export   AUTHOR_TESTING=1

````
NB: you can also copy the template config file in t/config/test_config.tpl to t/config/test_config.ini to use API credentials in your testing 

For verbose test
make test TEST_VERBOSE=1


### To-dos
* Simplify this README - TLDNR
* Classes for all Xero Components ( Item, Contact, Invoice etc )
* Working Public Application Example 

LICENSE AND COPYRIGHT
----

Copyright 2016-2018 Peter Scott.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

http://www.perlfoundation.org/artistic_license_2_0

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


### Contributors / Support

Want to contribute? Great, [get in touch!](mailto:peter@computerpros.com.au)
Need some help with your setup - will try to help where I can.

Many thanks to the following for help and suggestions:

  * Neil Grooby from [Xero Developer Team](https://developer.xero.com/)
  * Steve Bertrand for advice on [Perlmonks](https://perlmonks.org) 

[Xeroizer]: <https://github.com/waynerobinson/xeroizer/>
[Developer Blog]: <https://xero.computerpros.net.au>
  

