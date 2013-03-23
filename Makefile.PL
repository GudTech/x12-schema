#!/usr/bin/env perl
# IMPORTANT: if you delete this file your app will not work as
# expected.  You have been warned.
use inc::Module::Install;

name 'X12-Schema';
all_from 'lib/X12/Schema.pm';

requires 'Carp';
requires 'DateTime';
requires 'File::Slurp';
requires 'Moose';
requires 'Moose::Role';
requires 'namespace::autoclean';
requires 'Try::Tiny';

#install_script glob('script/*.pl');
#auto_install;
WriteAll;
