package App::sh2p::Utils;

use warnings;
use strict;

sub App::sh2p::Parser::convert (\@\@);
use constant (BREAK => 0x07);

our $VERSION = '0.04';

require Exporter;
our (@ISA, @EXPORT);
@ISA = ('Exporter');
@EXPORT = qw (Register_variable  Register_env_variable
              Delete_variable    get_variable_type
              print_types_tokens reset_globals
              iout               out                error_out    flush_out
              get_special_var    set_special_var    can_var_interpolate
              mark_function      unmark_function    ina_function
              mark_subshell      unmark_subshell    ina_subshell
              inc_block_level    dec_block_level    get_block_level
              is_user_function   set_user_function  unset_user_function
              dec_indent         inc_indent         
              rem_empty_string   fix_print_arg
              no_semi_colon      reset_semi_colon   query_semi_colon
              set_in_quotes      unset_in_quotes    query_in_quotes
              set_shell          which_shell
              open_out_file      close_out_file);

############################################################################

my $g_indent_spacing = 4;

my %g_special_vars = (
      'IFS'      => '" \t\n"',
      'ERRNO'    => '$!',
      'HOME'     => '$ENV{HOME}',
      'PATH'     => '$ENV{PATH}',
      'FUNCNAME' => '(caller(0))[3]',    # Corrected 0.04
      '?'        => '($? >> 8)',
      '#'        => 'scalar(@ARGV)',
      '@'        => '@ARGV',
      '*'        => '@ARGV',    # Should do a join with IFS
      '-'        => 'not supported',
      '$'        => '$$',
      '!'        => 'not supported'
      );

# This hash keeps a key for each variable declared
# so we know if to put a 'my' prefix
my %g_variables;

# This hash keeps track of environment variables
my %g_env_variables;

my %g_user_functions;
my $g_new_line       = 1;
my $g_use_semi_colon = 1;
my $g_ina_function   = 0;
my $g_ina_subshell   = 0;
my $g_block_level    = 0;
my $g_indent         = 0;
my $g_errors         = 0;
my $g_is_in_quotes   = 0;
my $g_shell_in_use   = "ksh";

my $g_outh;
my $g_filename;
my $g_out_buffer;
my $g_err_buffer;

#  For use by App::sh2p only
############################################################################
# Called by Handlers::interpolate
sub can_var_interpolate {

   my ($name) = @_;
   my $retn;
   
   $retn = get_special_var ($name, 1);
   
   if (defined $retn && $retn !~ /^[\$\@]/) {
       return 0
   }
   else {
       return 1
   }
}
########################################################
# This is primarily for [@] and [*].  Also to prevent globbing inside ""
sub query_in_quotes {
    return $g_is_in_quotes;
}

sub set_in_quotes {
    $g_is_in_quotes = 1;
}

sub unset_in_quotes {
    $g_is_in_quotes = 0;
}

############################################################################

sub get_special_var {
   my ($name, $no_errors) = @_;
   my $retn;
   
   return undef if ! defined $name;

   $no_errors = 0 if ! defined $no_errors;

   # Remove dollar prefix
   $name =~ s/^\$//;
   
   if ($name eq '0') {
       $retn = '$0';
   }
   elsif ($name =~ /^(\d+)$/) {
       my $offset = $1 - 1;
       $retn = "\$ARGV[$offset]";
   }
   elsif ($name eq 'PWD') {
       
       if (!$no_errors) {
           error_out ("Using \$PWD is unsafe: use Cwd::getcwd");
       }
       $retn = '$ENV{PWD}';
   }
   else {
       $retn = $g_special_vars{$name};
   }

   # In a subroutine we use @_
   if (defined $retn && $g_ina_function) {
       $retn =~ s/ARGV/_/;
   }
   
   return $retn;
}

############################################################################

sub set_special_var {
   my ($name, $value) = @_;
   
   $g_special_vars{$name} = $value;
   
   return $value;
}

############################################################################

sub no_semi_colon() {
    $g_use_semi_colon = 0;
}

sub reset_semi_colon() {
    $g_use_semi_colon = 1;
}

sub query_semi_colon() {
    return $g_use_semi_colon;
}

############################################################################

sub set_shell {
    my $shell = shift;
    $g_shell_in_use = $shell;
    #print STDERR "Shell set to <$shell>\n";
}

sub which_shell {
    return $g_shell_in_use;
}

#################################################################################

sub mark_function {
    $g_ina_function++;
}

sub unmark_function {
    $g_ina_function--;
    
    if ($g_ina_function < 0) {
        print STDERR "++++ Internal Error, function count = $g_ina_function\n";
    }
}

sub ina_function {
    return $g_ina_function;
}

#################################################################################

sub mark_subshell {
    $g_ina_subshell++;
}

sub unmark_subshell {

    # Delete all the variables for this subshell
    
    while (my($key, $value) = each %g_variables) {
          if ($value->[2] == $g_ina_subshell) {
              delete $g_variables{$key};
          }
    }

    $g_ina_subshell--;
    
    if ($g_ina_subshell < 0) {
        print STDERR "++++ Internal Error, subshell count = $g_ina_subshell\n";
    }
}

sub ina_subshell {
    return $g_ina_subshell;
}

############################################################################
# Return TRUE if NOT already registered
sub Register_variable {
    
    my ($name, $type) = @_;
    my $level  = get_block_level();
    
    if (! defined $type) {
        $type = '$'
    }
    
    #print STDERR "Register_variable: <$name> <$type> <$level> <$subshell>\n";
    
    if (exists $g_variables{$name}) {
    
       if ($g_variables{$name}->[0] <= $level && 
           $g_variables{$name}->[2] == $g_ina_subshell) { 
           return 0
       }
       else {
           # Create the variable with the block level and type	          
           $g_variables{$name} = [$level, $type, $g_ina_subshell];
           return 1
       }
    }
    elsif (exists $g_env_variables{$name}) {
    
       $g_env_variables{$name} = undef; 
       return 0;
    }
    else {
       # Create the variable with a block level and type
       
       $g_variables{$name} = [$level, $type, $g_ina_subshell];
       return 1
    } 
}

############################################################################

sub Register_env_variable {
    my ($name) = @_;
    
    # Does not matter if it already exists, or its type
    $g_env_variables{$name} = undef; 
}

############################################################################

sub get_variable_type {

    my ($name) = @_;
    my $level  = get_block_level();
        
    if (exists $g_variables{$name}) {
  
       if ($g_variables{$name}->[0] <= $level) {
           return $g_variables{$name}->[1]
       }
    }
    
    return '$';      # default
}

############################################################################
# Called by unset and export
sub Delete_variable {
    my ($name) = @_;
    my $level  = get_block_level();
        
    if (exists $g_variables{$name}) {
       if ($g_variables{$name} <= $level) {
           delete $g_variables{$name}
       }
    }
   
}

#################################################################################

sub inc_block_level {
    $g_block_level++;
}

sub dec_block_level {
    
    # Remove registered variables of current block level
    while (my($key, $value) = each (%g_variables)) {
        delete $g_variables{$key} if $value == $g_block_level
    }
    
    $g_block_level--;
    
    if ($g_block_level < 0) {
        print STDERR "++++ Internal Error, block level = $g_block_level\n";
    }
}

sub get_block_level {
    return $g_block_level;
}

#################################################################################

sub is_user_function {
   my ($name) = @_;

   return (exists $g_user_functions{$name})
}

sub set_user_function {
   my ($name) = @_;

   $g_user_functions{$name} = undef;
   
   return 1;   # true
}

sub unset_user_function {
   my ($name) = @_;
   
   delete $g_user_functions{$name} if exists $g_user_functions{$name};
   
   return 1;   # true
}

#################################################################################

sub mark_new_line {
    $g_new_line = 1;
}

sub new_line {
    return $g_new_line;
}

#################################################################################

sub inc_indent { $g_indent++ if $g_indent < 80 }
sub dec_indent { $g_indent-- if $g_indent > 0  }

#################################################################################

sub open_out_file {
    my ($g_filename, $perms) = @_;
    
    if ($g_filename eq '-') {
        $g_outh = *STDOUT;
    }
    else {
        open ($g_outh, '>', $g_filename) || die "$g_filename: $!\n";
        
        # fchmod is not implemented on all platforms
        chmod ($perms, $g_filename) if defined $perms;
        print STDERR "Processing $g_filename:\n";
    }
    
    $g_out_buffer = '';
    $g_err_buffer = '';
}

sub close_out_file {
    
    flush_out ();
    
    close ($g_outh);
    print STDERR "\n";
    $g_filename = undef;
}

#################################################################################
# Indented out
sub iout {

   #print $g_outh ' ' x ($g_indent * $g_indent_spacing);
   
   my (@args) = @_;
  
   if (query_semi_colon()) {
       unshift @args, (' ' x ($g_indent * $g_indent_spacing));
   }
   
   out (@args);
}

#################################################################################

sub out {
   
   local $" = '';
   my $line = "@_";
   
   #my @caller = caller();
   #print STDERR "out: <$line> @caller\n";
   
   $g_out_buffer .= $line;
      
   $g_new_line = 0;
   
}

################################################################################
# I don't like these hacks, but any other way is convoluted
sub fix_print_arg {
    # This avoids 'print (...) interpreted as function'
    #print STDERR "rem_empty_string: <$g_out_buffer>\n";
    
    if ($g_out_buffer =~ /print/) {
        $g_out_buffer =~ s/(^|[^\'\"]+)(print\s+)\(/$2\"\",(/;    
    }
}

sub rem_empty_string {
    
    return if $g_out_buffer =~ /print/;   # Often required

    # Remove "". at start of calls
    $g_out_buffer =~ s/\(\"\"\./(/;
    
    # Remove "". in assignments
    $g_out_buffer =~ s/= \"\"\./= /;
    
}

################################################################################

sub error_out {
    my $msg = shift;
    
    if (defined $msg) {
        $msg = "**** INSPECT: $msg\n";
    }
    else {
        $msg = "\n";
    }

    $g_err_buffer .= "# $msg";
    
    $g_errors++;
}

#################################################################################

sub flush_out {
     
   print $g_outh $g_err_buffer;
   print $g_outh $g_out_buffer;
      
   # Leading space for readability with multiple files
   $g_err_buffer =~ s/\#/ \#/g;
   print STDERR $g_err_buffer; 
   
   $g_out_buffer = '';
   $g_err_buffer = '';
}

#################################################################################

sub reset_globals {

    %g_variables      = ();
    %g_env_variables  = ();
    %g_user_functions = ();
    
    $g_out_buffer     = '';
    $g_err_buffer     = '';
      
    $g_new_line       = 1;
    $g_use_semi_colon = 1;
    $g_ina_function   = 0;
    $g_ina_subshell   = 0;
    $g_block_level    = 0;
    $g_indent         = 0;
    $g_errors         = 0;
    $g_is_in_quotes   = 0;
    $g_shell_in_use   = "ksh";
    
}

#################################################################################
# Debug purposes only
sub print_types_tokens {
    
    my ($types, $tokens) = @_;
    my $caller = (caller(1))[3];
    
    for (my $i = 0; $i < @$types; $i++) {
    
        print STDERR "$caller Type: ".$types->[$i][0].", ";
        
        print STDERR "Token: ".$tokens->[$i]."\n";
    }
    
    if (@$types != @$tokens) {
        print STDERR "Types array: ".@$types.", Token array: ".@$tokens."\n";
    }
}

#################################################################################

# Module end
1;
