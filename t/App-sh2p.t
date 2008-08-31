# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl App-sh2p.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 8;
# BEGIN { use_ok('App::sh2p') };

use_ok('App::sh2p::Builtins');
use_ok('App::sh2p::Compound');
use_ok('App::sh2p::Handlers');
use_ok('App::sh2p::Here');
use_ok('App::sh2p::Operators');
use_ok('App::sh2p::Parser');
use_ok('App::sh2p::Runtime');
use_ok('App::sh2p::Utils');

#########################

# Tests to be supplied
# 

