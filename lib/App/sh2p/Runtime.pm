package App::sh2p::Runtime;

use strict;
use warnings;

our $VERSION = '0.02';

require Exporter;
our (@ISA, @EXPORT);
@ISA = ('Exporter');
@EXPORT = qw (sh2p_read_from_stdin sh2p_read_from_here);

######################################################
# read_from_handle
# Arguments:
#       1. Handle
#	2. Value of $IFS
#	3. Prompt string
#	4. List of scalar references
#	Any may be undef

sub read_from_handle {

   my ($handle, $IFS, $prompt, @refs) = @_;
   
   if (!defined $IFS) {
      $IFS = " \t\n";
   }
   
   if (defined $prompt) {
      print $prompt
   }
   
   my $line = <$handle>;
   my $REPLY;
   
   chomp $line;
   
   my (@vars) = split /[$IFS]+/, $line;
   my $i;
   
   # Assign values to variables
   for ($i = 0; $i < @refs; $i++) {
      if ($i > $#vars) {
         ${$refs[$i]} = '';
      }
      else {
         ${$refs[$i]} = $vars[$i];
      }
   }
   
   # If not enough variables supplied
   if ($i < $#vars || !@refs) {
      my $IFS1st = substr($IFS,0,1);
      $REPLY = join $IFS1st, @vars[$i..$#vars];
   }

   if (@refs > 0 && defined $REPLY) {
      # Concat extra values onto the element
      ${$refs[-1]} .= " $REPLY";
      $REPLY = ''
   }
   
   return $REPLY
}

######################################################

sub sh2p_read_from_stdin {

   my (@args) = @_;
   
   return read_from_handle (*STDIN, @args);
}

######################################################

sub sh2p_read_from_here {

   my ($filename, @args) = @_;

   open (my $handle, '<', $filename) or die "Unable to open $filename: $!";
   
   return read_from_handle ($handle, @args);
}

######################################################

# Module end
1;
