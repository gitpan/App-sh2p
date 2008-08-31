package App::sh2p::Operators;

use warnings;
use strict;
use App::sh2p::Utils;

sub App::sh2p::Parser::convert (\@\@);
use constant (BREAK => '@');

our $VERSION = '0.01';

######################################################

sub no_change {

   out $_[0];
   return 1;
}

sub boolean {

   my ($op) = shift;
   
   if (substr($op,0,1) eq '-' && length($op) eq 2) {
       out "$op ";
   }
   else {
       out " $op ";
   }
   
   return 1;
}

# Module end
1;