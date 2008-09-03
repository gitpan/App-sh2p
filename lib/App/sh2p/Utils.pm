package App::sh2p::Utils;

use warnings;
use strict;
use Data::Dumper;   # for debug purposes

sub App::sh2p::Parser::convert (\@\@);
use constant (BREAK => '@');

our $VERSION = '0.02';

require Exporter;
our (@ISA, @EXPORT);
@ISA = ('Exporter');
@EXPORT = qw (Register_variable  Delete_variable    get_variable_type
              print_types_tokens reset_globals
              iout               out                error_out
              get_special_var    set_special_var
              mark_function      unmark_function    ina_function
              inc_block_level    dec_block_level    get_block_level
              is_user_function   set_user_function
              dec_indent         inc_indent 
              no_semi_colon      reset_semi_colon   query_semi_colon
              open_out_file      close_out_file);

############################################################################

my $g_indent_spacing = 4;

my %g_special_vars = (
      'IFS'   => '" \t\n"',
      'ERRNO' => '\$!',
      '?'     => '($? >> 8)',
      '#'     => 'scalar(@ARGV)',
      '@'     => '@ARGV',
      '*'     => '@ARGV',    # Should do a join with IFS
      '-'     => 'not supported',
      '$'     => '$$',
      '!'     => 'not supported'
      );

# This hash keeps a key for each variable declared
# so we know if to put a 'my' prefix
my %variables;

my %g_user_functions;
my $g_new_line       = 1;
my $g_use_semi_colon = 1;
my $g_ina_function   = 0;
my $g_block_level    = 0;
my $g_indent         = 0;
my $g_errors         = 0;
my $g_line_number    = 1;

my $g_outh;
my $g_filename;

#  For use by App::sh2p only
############################################################################

sub get_special_var {
   my ($name) = @_;
   my $retn;
   
   return undef if ! defined $name;
   
   # Remove dollar prefix
   $name =~ s/^\$//;
   
   if ($name =~ /^(\d+)$/) {
       my $offset = $1 - 1;
       $retn = "\$ARGV[$offset]";
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

############################################################################
# Return TRUE if NOT already registered
sub Register_variable {
    
    my ($name, $type) = @_;
    my $level  = get_block_level();
    
    if (! defined $type) {
        $type = '$'
    }
    
    #print STDERR "Register_variable: <$name> <$type> <$level>\n";
    
    if (exists $variables{$name}) {
    
       if ($variables{$name}->[0] <= $level) {
           return 0
       }
       else {
           # Possible change of type ?
           return 1
       }
    }
    else {
       # Create the variable with a block level and type
       
       $variables{$name} = [$level, $type];
       return 1
    } 
}

############################################################################

sub get_variable_type {

    my ($name) = @_;
    my $level  = get_block_level();
        
    if (exists $variables{$name}) {
  
       if ($variables{$name}->[0] <= $level) {
           return $variables{$name}->[1]
       }
    }
    
    return '$';      # default
}

############################################################################
# Called by unset
sub Delete_variable {
    my ($name) = @_;
    my $level  = get_block_level();
        
    if (exists $variables{$name}) {
       if ($variables{$name} <= $level) {
           delete $variables{$name}
       }
    }
   
}

#################################################################################

sub inc_block_level {
    $g_block_level++;
}

sub dec_block_level {
    
    # Remove registered variables of current block level
    while (my($key, $value) = each (%variables)) {
        delete $variables{$key} if $value == $g_block_level
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
    $g_filename = shift;
    
    if ($g_filename eq '-') {
        $g_outh = *STDOUT;
    }
    else {
        open ($g_outh, '>', $g_filename) || die "$g_filename: $!\n";
        print STDERR "Processing $g_filename:\n";
    }
}

sub close_out_file {
    
    close ($g_outh);
    print STDERR "\n";
    $g_filename = undef;
}

#################################################################################
# Indented out
sub iout {

   print $g_outh ' ' x ($g_indent * $g_indent_spacing);
   
   #if ($_[0] =~ /^my/) {
   #    my @caller = caller();
   #    print "iout my: @caller\n";
   #}
   
   out (@_);
}

#################################################################################

sub out {

   #print STDERR "\nout <@_>\n";
   #my @caller = caller();
   #print STDERR "Called from @caller\n";
   
   my $line = "@_";
   
   while ($line =~ /\n/g) {
       $g_line_number++
   }
   
   print $g_outh $line;
   
   $g_new_line = 0;
}

#################################################################################

sub error_out {
    my $msg = shift;
    
    if (defined $msg) {
        $msg = "**** INSPECT: $msg\n";
        printf STDERR " %03d %s", $g_line_number, $msg;
    }
    else {
        $msg = "\n";
    }
    
    out "# $msg";
    $g_line_number++;
    
    $g_errors++;
}

#################################################################################

sub reset_globals {

    my %variables = ();

    my %g_user_functions;
    my $g_new_line       = 1;
    my $g_use_semi_colon = 1;
    my $g_ina_function   = 0;
    my $g_block_level    = 0;
    my $g_indent         = 0;
    my $g_errors         = 0;
    my $g_line_number    = 1;
}

#################################################################################
# Debug purposes only
sub print_types_tokens (\@\@) {
    
    my ($types, $tokens) = @_;
    
    for (my $i = 0; $i < @$types; $i++) {
    
        print STDERR "Token: $tokens->[$i], type: $types->[$i][0]\n";
    }
}

#################################################################################

# Module end
1;