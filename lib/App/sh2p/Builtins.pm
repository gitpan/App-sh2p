package App::sh2p::Builtins;

use strict;
use Getopt::Std;
use App::sh2p::Utils;
use App::sh2p::Parser;
use App::sh2p::Here;

sub App::sh2p::Parser::convert (\@\@);
use constant (BREAK => '@');

our $VERSION = '0.03';

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
    my $new_func = (App::sh2p::Parser::get_perl_builtin($func))[1];
    
    error_out ("$func replaced by Perl built-in $new_func\n".
               " #               Check arguments and return value");
    
    return general_arg_list($new_func, @args);
}

########################################################

sub general_arg_list {
    my ($cmd, @args) = @_;
    my $ntok = 1;
    my $last = '';
    
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
        if ($arg !~ /^\d$/) {
            # Escape embedded quotes
            $arg =~ s/\"/\\\"/g;
            #"help syntax highlighter
            $arg = "\"$arg\"";
        }
    }
    
    iout "$cmd (".join(',',@args).")$semi $last";
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

   my (undef, $directory) = @_;
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
# also used by chown
sub do_chmod {
    
    my ($cmd, $perms, @args) = @_;
    my $ntok = 1;
    #my @args = split /\s+/, $args;
    my $comment = '';
    
    iout "$cmd ";
    
    if (defined $perms) {
        $ntok++;
        
        if ($cmd eq 'chmod') {
            out "0$perms,";
        }
        else {
            out "$perms,";
        }
        
        if (@args) {
        
            for (my $i=0; $i < @args; $i++) {
                
	        $ntok++;
	        
	        if (substr ($args[$i],0,1) eq '#') {
	            my @comment = splice (@args,$i);
	            $comment = "@comment";
	            
	            # remove trailing comment from previous item
	            $args[$i-1] =~ s/,$// if $i > 0;
	            last
	        }
	        
	        # Escape embedded quotes
	        $args[$i] =~ s/\"/\\\"/g;
	        #"help syntax highlighter
	        $args[$i] = "\"$args[$i]\"";
	        $args[$i] .= ',' if $i < $#args;
	    } 
	          
            App::sh2p::Handlers::interpolation ("@args");
        }
    }
    out "; $comment\n";
    
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

sub do_integer {
    
    # $cmd should be 'integer'
    my ($cmd, $action, @rest) = @_;
    
    my $var = $action;
    
    # Remove any assignment from the name
    $var =~ s/=.*//;
           
    if (Register_variable ("\$$var", 'int') ) {
       iout 'my ';
    }
    
    my $retn = App::sh2p::Handlers::Handle_assignment ($action, @rest);
    
    $retn++;   # $cmd
    return $retn;
}

########################################################

sub do_kill {
    my ($cmd, @rest) = @_;
    my $signal = 'TERM';   # default signal
    
    # Remove the hyphen - it has a different meaning in Perl!
    if ($rest[0] =~ s/^-//) {
        $signal = shift @rest;
    }

    return general_arg_list ($cmd, $signal, @rest);
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
   
   getopts ('p:rsunAa', \%args);
   
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
       if (exists $args{a} || exists $args{A}) {
           $var = "\@$var";
           if (Register_variable($var, '@')) {
               iout "my $var;\n";
           }
       }
       else {
           $var = "\$$var";
           if (Register_variable($var, '$')) {
               iout "my $var;\n";
           }
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

sub do_return {

   my ($name, $arg) = @_;
   my $ntok = 1;

   iout $name;
   
   if (defined $arg            && 
       substr($arg,0,1) ne '#' && 
       substr($arg,0,1) ne ';'    ) {
       
      out ' ';
      my @tokens = ($arg);
      my @types  = App::sh2p::Parser::identify (1, @tokens); 
                                                
      App::sh2p::Parser::convert (@tokens, @types);
      $ntok++;
   }

   out ";";
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
# typeset [[+-Ulprtux] [-L[n]]  [-R[n]]  [-Z[n]]  [-i[n]]  |  -f  [-tux]]
#         [name[=value] ...]
# Needs more work!
sub do_typeset {
   
   my $ntok = @_;
   my %args;
   
   # First argument should be 'typeset'
   shift @_;
   
   local @ARGV = @_;
   
   getopts ('UPRTUXLRZ:iftux', \%args);
   
   my %type = (i => 'int',
               l => 'lc',
               u => 'uc',
               Z => '%0nd',
               L => '%-s',
               R => '%s',
               X => '%X',
               x => '%x');
   
   my $type = '$';
   my @opt = grep {$args{$_}} keys %args;
   
   if (exists $type{$opt[0]}) {
      $type = $type{$opt[0]};
   }

   # These types are not yet supported by other functions
   if (@opt > 1) {
       if ( $args{Z} && defined $args{Z}) {
           $type =~ s/n/$args{Z}/;
       }
       else {
           error_out "Only one option supported for typedef or declare";
       }
   }

   my $var = $ARGV[0];

   # Remove any assignment for the name
   $var =~ s/=.*//;
   
   if (Register_variable ("\$$var", $type) ) {
          iout 'my ';
   }
    
   $ntok += App::sh2p::Handlers::Handle_assignment (@ARGV);
   
   return $ntok;
}

########################################################
# Also does for echo
sub do_print {

   my $ntok = 1;
   my ($name, @args) = @_;
   my $newline = 1;
   my $handle = '';
   
   my $opt_u;
   my %args;
   local @ARGV;

   my $redirection = '';
   my $file = '';

   for my $arg (@args) {
       last if $arg eq BREAK || $arg eq ';';
       
       my $quotes = 0;
       # This is so a > inside a string is not seen as redirection
       if ($arg =~ /^([\"\']).*?\1/) {
           $quotes = 1;
       }
       
       # This should also strip out the redirection
       if (!$quotes && $arg =~ s/(\>{1,2})//) {
           $redirection = $1;     
       }
       
       if ($arg && $redirection && (! $file)) {
           $arg =~ s/(\S+)//;
           $file = $1;
       }
       
       push @ARGV, $arg if $arg;
       $ntok++;
   }
   
   if ($redirection) {
       App::sh2p::Handlers::Handle_open_redirection ($redirection, $file);    
       $handle = '$sh2p_handle ';
   }
   
   getopts ('nEepu:', \%args);
      
   # Ignore -e and -E options (from echo)
   if (exists $args{n}) {
       $newline = 0;
   }
   
   if ($name eq 'print') {
       if (exists $args{p}) {
           error_out ('Pipes/co-processes are not supported, use open');
       }
       
       if (exists $args{u} && defined $args{u}) {
           my @handles = ('', 'STDOUT ', 'STDERR ');
           if ($args{u} > $#handles) {
               error_out ('file descriptors not currently supported');
               $handle = "$args{u} ";  # Just to show something 
           }
           else {
               $handle = $handles[$args{u}];
           }
       }
   }
   
   iout ("print $handle");
   
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
   
   App::sh2p::Handlers::Handle_close_redirection() if $redirection;
   
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
      
      # Fix for 5.6 01/09/2008
      iout "my \@${array}\[0..". $#values ."\] = qw(@values);\n";
}

########################################################

sub do_unset {
   
   my ($undef, $var) = @_;
   my $ntok = 1;
   
   iout 'undef ';

   if (defined $var && substr($var,0,1) ne '#') {
      my $type = '$';
      
      if (get_special_var($var)) {
          set_special_var(undef);
      }
      else {
          $type = get_variable_type($var);
          Delete_variable ($var);
      }
      
      $var = $type.$var;
      
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
