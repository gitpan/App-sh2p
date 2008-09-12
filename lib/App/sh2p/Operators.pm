package App::sh2p::Operators;

use warnings;
use strict;
use App::sh2p::Utils;

sub App::sh2p::Parser::convert (\@\@);
use constant (BREAK => 0x07);

our $VERSION = '0.03';
my $g_specials = '\[|\*|\?';
   
######################################################

sub no_change {
   my ($op, @rest) = @_;
   
   out $op;
   
   return 1;
}

######################################################

sub shortcut {
   my ($input) = @_;
   
   my $op;
   
   # operators are followed by whitespace
   if ($input =~ s/(.+?)\s+//)  { 
       $op = $1;
   }
   else {
       $op = $input;
       $input = '';     # Avoid recursion
   }
   
   out "$op ";
   
   if ($input) {
       my @tokens = ($input);
       my @types  = App::sh2p::Parser::identify (1, @tokens); 
                                                       
       App::sh2p::Parser::convert (@tokens, @types);
   }
   
   return 1;
}

######################################################

sub boolean {

   my ($op) = @_;
   my $ntok = 1;
   
   if (substr($op,0,1) eq '-' && length($op) eq 2) {
       out "$op ";
   }
   else {
       out " $op ";
   }
   
   return $ntok;
}

######################################################
# Used for patterns like +([0-9]) -> [0-9]+
sub swap1stchar {
    my ($op) = @_;
    my $ntok = 1;
    
    # Remove parentheses & swap quanifier
    $op =~ s/(.)(\(.+\))/$2$1/;
    
    $op = App::sh2p::Compound::glob2pat($op);

    out " /$op/ ";
    
    return $ntok;
}

######################################################
# Used for patterns like @(one|two) -> (one|two)
sub chop1stchar {
    my ($op) = @_;
    my $ntok = 1;
    
    # Remove first char
    $op =~ s/^.//;
    
    $op = App::sh2p::Compound::glob2pat($op);

    out " /$op/ ";
    
    return $ntok;
}

######################################################

# Module end
1;
