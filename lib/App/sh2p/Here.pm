package App::sh2p::Here;

# I expect only one active here doc at a time, 
# but I guess they could be in nested loops
#     while read var1
#     do
#        while read var2
#        do
#           ...
#        done << HERE
#           ...
#        HERE
#     done << HERE
#        ...
#     HERE
# This would create a problem, since the filename
# is based on the here label - TODO
#
use strict;
use Carp;
use Scalar::Util qw(refaddr);

use App::sh2p::Utils;

#################################################################################

my %handle;
my %name;
my %access;

my $g_last_opened_name;

#################################################################################

sub get_last_here_doc {

   my $name = $g_last_opened_name;
   $g_last_opened_name = undef;
   return $name

}

#################################################################################

sub _get_dir {
   my $dir;
   
   if (defined $ENV{SH2P_HERE_DIR}) {
      $dir = $ENV{SH2P_HERE_DIR}
   }
   else {
      $dir = '.'
   }
   return $dir;
}

#################################################################################

sub open {
   my ($class, $name, $access) = @_;
   
   my $this = bless \do{my $some_scalar}, $class;
   my $key = refaddr $this;
   
   $name  {$key} = $name;
   $access{$key} = $access;
   
   my $dir = _get_dir();
   $g_last_opened_name = $name;
   
   error_out ("Writing $dir/$name.here");
   open ($handle{$key}, $access{$key}, "$dir/$name.here") ||
        carp "Unable to open $dir/$name.here: $!\n";
   
   return $this 
}

#################################################################################

sub write {
   my ($this, $buffer) = @_;
   my $key = refaddr $this;

   my $handle = $handle{$key};

   print $handle ("$buffer\n") or 
         carp "Unable to write to $name{$key}: $!";

}

#################################################################################

sub read {
   my ($this) = @_;
   my $key = refaddr $this;

   return <$handle{key}>
}

#################################################################################

sub close {
   my ($this) = @_;
   my $key = refaddr $this;

   my $retn = close $handle{$key};
   delete $handle{$key};
   delete $name  {$key};
   delete $access{$key};

   return $retn;
}

#################################################################################

sub DESTROY {
   my ($this) = @_;
   my $key = refaddr $this;

   if (exists $name{$key}) {
      close_here_doc ($this);
   }
}

#################################################################################
1;