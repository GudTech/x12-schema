#!/usr/bin/env perl
# IMPORTANT: if you delete this file your app will not work as
# expected.  You have been warned.
use inc::Module::Install;

name 'GTCore';
all_from 'lib/GTCore.pm';

requires 'parent';
requires 'DBR';
requires 'MIME::Base64' => 3.11;
requires 'Crypt::OpenSSL::DSA' => 0.01;
requires 'Moose' => 2.04;

#install_script glob('script/*.pl');
#auto_install;
WriteAll;
