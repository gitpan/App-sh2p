package App::sh2p::Builtins;

use strict;
use Getopt::Std;
use App::sh2p::Utils;
use App::sh2p::Parser;
use App::sh2p::Here;

sub App::sh2p::Parser::convert (\@\@);
use constant (BREAK => '@');

our $VERSION = '0.02';

########################################################
# For builtins/functionality that cannot be implemented
sub not_implemented {
   error_out "The following line cannot be translated:";
   error_out "@_";

   return scalar(@_);
}

########################################################

sub one4one {

    my ($func, @args) = @_;
    my $ntok = 1;
    my $last = '';
    my $new_func = (App::sh2p::Parser::get_perl_builtin($func))[1];
    
    error_out ("$func replaced by Perl built-in $new_func");
    error_out ("Check arguments and return value");
    
    # Is final token a comment?
    if (substr($args[-1],0,1) eq '#') {
        $last = pop @args;
        $ntok++;
    }
    
    my $semi = '';
    $semi = ';' if query_semi_colon();
          
    # Parse arguments
    for my $arg (@args) {           
        $ntok++;
        # Escape embedded quotes
        $arg =~ s/\"/\\\"/g;
        #"help syntax highlighter
        $arg = "\"$arg\"";
    }
    
    iout "$new_func (".join(',',@args).")$semi $last";
    iout "\n" if query_semi_colon();
    
    return $ntok;
}

########################################################

sub advise {

    my ($func, @args) = @_;
    my $ntok = @_;
    my $last = '';
        
    my $advise = (App::sh2p::Parser::get_perl_builtin($func))[1];
    
    error_out ("$func should be replaced by something like $advise");
    
    # Is final token a comment?
    if (substr($args[-1],0,1) eq '#') {
        $last = pop @args;
        $ntok++;
    }
    
    my $semi = '';
    $semi = ';' if query_semi_colon();
    
    iout "$func (".join(',',@args).")$semi $last";
    iout "\n" if query_semi_colon();
    
    return $ntok;
}

########################################################

sub do_break {

   my ($undef, $level) = @_;
   my $ntok = 1;
   
   iout 'last';
   
   if (defined $level && $level =~ /^\d+$/) {
      error_out "Multiple levels in 'break $level' not supported";
      $ntok++;
   }

   return $ntok;
}

########################################################

sub do_continue {

   my ($undef, $level) = @_;
   my $ntok = 1;
   
   iout 'next';
   
   if (defined $level && $level =~ /^\d+$/) {
      error_out "Multiple levels in 'continue $level' not supported";
      $ntok++;
   }

   return $ntok;
}

########################################################

sub do_cd {

   my ($undef, $directory) = @_;
   my $ntok = 1;
   
   iout 'chdir ';
   
   if (defined $directory && substr($directory,0,1) ne '#') {
      my @tokens = ($directory);
      my @types  = App::sh2p::Parser::identify (1, @tokens); 
                        
      App::sh2p::Parser::convert (@tokens, @types);
      $ntok++;
   }
   out ";\n";
   
   return $ntok;
}

########################################################

sub do_exit {

   my ($cmd, $arg) = @_;
   my $ntok = 1;
   
   if (defined $arg) {
       iout ("exit ($arg);\n");
       $ntok++;
   }
   else {
       iout ("exit;\n");
   }
   
   return $ntok;
}

########################################################

sub do_export {

   my $ntok = @_;
   # First argument should be 'export'
   shift @_;
   
   # TODO - other export arguments
   
   for my $env (@_) {
      if  ($env =~ /^(\w+)=(.*)$/) {
         iout "\$ENV{$1} = $2;\n";
      }
      else {
         iout "\$ENV{$env} = \$$env;\n";
      }
   }
   
   return $ntok;
}

########################################################

sub do_expr {
     
     # $cmd should be expr
     my ($cmd, @rest) = @_;
     my $ntok = 1;
     
     # temporary fix
     error_out ('Suspious conversion from expr');
     iout ("@rest");
     
     return $ntok; 
}

########################################################

sub do_source {

   my ($undef, $file) = @_;
   my $ntok = 1;
   
   error_out ();
   error_out "sourced file should also be converted\n";
   out 'do ';
   
   if (defined $file && substr($file,0,1) ne '#') {
      my @tokens = ($file);
      my @types  = App::sh2p::Parser::identify (1, @tokens); 
                                                
      App::sh2p::Parser::convert (@tokens, @types);
      $ntok++;
   }

   out ";";
   return $ntok;
}

########################################################

sub do_return {

   my ($name, $arg) = @_;
   my $ntok = 1;
   
   iout "$name ";
   
   if (defined $arg && substr($arg,0,1) ne '#') {
      my @tokens = ($arg);
      my @types  = App::sh2p::Parser::identify (1, @tokens); 
                                                
      App::sh2p::Parser::convert (@tokens, @types);
      $ntok++;
   }

   out ";";
   return $ntok;
}

########################################################
# typeset [[+-Ulprtux] [-L[n]]  [-R[n]]  [-Z[n]]  [-i[n]]  |  -f  [-tux]]
#         [name[=value] ...]
# Needs more work!
sub do_typeset {
                 #typeset    =>   my   
                 #typeset –I =>   int
                 #typeset –l =>   lc
                 #typeset –u =>   uc 
                 #typeset -Z =>   sprintf               
   
   my $ntok = @_;
   my %args;
   
   # First argument should be 'typeset'
   shift @_;
   
   local @ARGV = @_;
   getopts ('UPRTUXLRZiftux', \%args);
   
   if (exists $args{i}) {
      error_out "integer attribute is not available";
   }
   
   for my $var (@ARGV) {
   
      if  ($var =~ /^(\w+)=(.*)$/) {
         iout "my \$$1 = $2;\n";
      }
      else {
         # Assume name
         iout "my \$$var;\n";
      }
   }
   
   return $ntok;
}

########################################################
# Also does for echo
sub do_print {

   my $ntok = 1;
   my ($name, @args) = @_;
   my $newline = 1;
   my %args;
   local @ARGV;
      
   for my $arg (@args) {
       last if $arg eq BREAK || $arg eq ';';
       push @ARGV, $arg;
       $ntok++;
   }
   
   getopts ('nEe', \%args);
      
   # Ignore -e and -E options (from echo)
   if (exists $args{n}) {
       $newline = 0;
   }
   
   iout ("print ");
   
   # C style for loop because I need to check the position
   for (my $i; $i < @ARGV; $i++) {
       my @args = ($ARGV[$i]);
       my @types  = App::sh2p::Parser::identify (2, @args);                                
       App::sh2p::Parser::convert (@args, @types);
       out ',' if $i < $#ARGV;
   }
   
   if ($newline) {
      out ",\"\\n\";"
   }
   
   out "\n";
   
   return $ntok;
}

########################################################

sub do_read {
   my %args;
   my $prompt = 'undef';
   my $ntok;
   local @ARGV;

   # First argument is 'read'
   shift @_;
   $ntok++;
   
   # Find end of statement
   for my $arg (@_) {   
      last if $arg eq BREAK || $arg eq ';';   # Inserted in sh2p loop
      push @ARGV, $arg;
      $ntok++;
   }
   
   getopts ('p:rsun', \%args);
   
   if (exists $args{p}) {               # Bash syntax
      $prompt = $args{p}
   }
   
   if ($ARGV[0] =~ /^(\w+)\?(.*)$/) {   # ksh syntax
      $prompt  = $2;
      $ARGV[0] = $1;
   }   

   # Add $ prefix to variable names   
   # Do I need to pre-define them?
   for my $var (@ARGV) {
       $var = "\$$var";
       if (Register_variable($var)) {
           iout "my $var;\n";
       }
   }
   
   my $heredoc = App::sh2p::Here::get_last_here_doc();
   
   if (defined $heredoc) {
      out "sh2p_read_from_here ('$heredoc', ".
             get_special_var('IFS').", $prompt, ".
             '\\'.(join ',\\', @ARGV).")";
   
   } 
   else {
      out "sh2p_read_from_stdin (".
             get_special_var('IFS').", $prompt,\n".
             '\\'.(join ',\\', @ARGV).");";
   }
   
   return $ntok;
}

########################################################
# Need getopt here, but it can't deal with +
#  set [+-abCefhkmnpsuvxX] [+-o [option]] [+-A name] [--] [arg ...]

sub do_set {
   
   my $ntok = @_;
   # First argument is 'read'
   shift @_;
   
   for my $option (@_) {
      my $act = substr($option, 0, 1);
      my $set = substr($option, 1);
      
      if ( $set eq 'A') {
         if ($act eq '-') {
            initialise_array (@_);
         }
         else {
            overwrite_array (@_);
         }
         
         last;
      }
   }  
   return $ntok;
}

# set -A
sub initialise_array {
   my ($nu, $array, @values) = @_;
   
   iout "my \@$array = qw(@values);\n";
}

# set +A
sub overwrite_array {
      my ($nu, $array, @values) = @_;
      
      iout "my \@${array}[0..". $#values ."] = qw(@values);\n";
}

########################################################

sub do_unset {
   
   my ($undef, $var) = @_;
   my $ntok = 1;
   
   iout 'undef ';
   
   if (defined $var && substr($var,0,1) ne '#') {
      my @tokens = ($var);
      my @types  = App::sh2p::Parser::identify (1, @tokens); 
                        
      App::sh2p::Parser::convert (@tokens, @types);
      $ntok++;
   }
   out ";\n";
   
   return $ntok;
}

########################################################

1;