package App::sh2p::Handlers;

use strict;

use App::sh2p::Parser;
use App::sh2p::Utils;
use App::sh2p::Here;

sub App::sh2p::Parser::convert (\@\@);
use constant (BREAK => '@');

our $VERSION = '0.02';

my $g_unterminated_backtick = 0;


#  For use by App::sh2p only
############################################################################

sub Handle_assignment {
   # Currently does not handle arrays
   
   my $ntok = 1;
   my ($in, @rest)  = @_;
   
   $in =~ /^(\w+)=(.*)$/;
   my $lhs = $1;
   my $rhs = $2;
   
   if ( !defined $rhs) {
      die "No rhs - not happy. <$in>"
   }
   
   if (defined get_special_var($lhs)) {
      set_special_var ($lhs, $rhs);
   }
   
   my $name = "\$$lhs";
   
   if (Register_variable ($name) ) {
       iout "my $name = ";
   }
   else {
       iout "$name = ";
   }
   
   if ( !defined $rhs || !$rhs ) {
      out 'undef'
   }
   else {
      # Process the rhs
      
      for my $tok (@rest) {
          last if substr($tok,0,1) eq '#';
          $rhs .= "$tok ";
          $ntok++;
      }
      
      my @tokens = App::sh2p::Parser::tokenise ($rhs);
      my @types  = App::sh2p::Parser::identify (1, @tokens); 
      
      # Avoid recursion
      die "Nested assignment $in" if $types[0] eq 'ASSIGNMENT';
      #print_types_tokens (@types, @tokens);
      
      App::sh2p::Parser::convert (@tokens, @types);
   }
   
   out ';';
   if ($ntok == @_) {
       out "\n";
   }
   
   return $ntok;
}

############################################################################

sub Handle_array_assignment {
   my $ntok = @_;
   my $in  = shift;
   
   $in =~ /^(\w+)\[(.*)\]=(.*)$/;
   
   my $arr = $1;
   my $idx = $2;
   my $rhs = $3;
   
   if ( !defined $rhs) {
      die "No rhs - not happy. <$in>"
   }
   
   # The shell allows a variable index without a '$'
   if ($idx =~ /^[[:alpha:]_]\w+/)  {  # No '$' (count + 1)
      $idx = "\$$idx";   
   }
   
   iout "\$$arr\[$idx\] = ";
      
   if ( !defined $rhs || !$rhs ) {
      out 'undef'
   }
   else {
      # Process the rhs
      
      my @tokens = App::sh2p::Parser::tokenise ($rhs);
      my @types  = App::sh2p::Parser::identify (1, @tokens); 
      
      # Avoid recursion
      die "Nested array assignment $in" if $types[0] eq 'ARRAY_ASSIGNMENT';
      
      App::sh2p::Parser::convert (@tokens, @types);
   }
   
   out ";\n";
   return $ntok;

}

############################################################################

sub Handle_break {
   # Maybe check to see if we are in a heredoc?
   out "\n";
   return 1;
}

############################################################################

sub Handle_variable {
   my $token = shift;
   my $new_token;
   
   # Check for specials
   if ($new_token = get_special_var($token)) {
      $token = $new_token;
   }
   elsif ( substr($token, 0, 2) eq '${' ) {
      # TODO Variable expansion
      
      # Strip out the braces
      $token =~ s/\$\{(.*)\}/\$$1/;
   }
   elsif ( substr($token, 0, 3) eq '$((' ) {
      # Calculation
      $token =~ s/\$\(\((.*)\)\)/$1/g;
      
   }
   elsif ( substr($token, 0, 2) eq '$(' ) {
      # Back-ticks
            
      $token =~ s/\$\((.*)\)/`$1`/g;
   }
      
   out $token;
   
   return 1;
}

############################################################################

sub Handle_delimiter {

   my $ntok;
   my ($tok) = @_;
   
   if ($tok =~ /^\(\((.+)=(.+)\)\)$/) {
      my $lhs = $1;
      my $rhs = $2;
      
      # Could be compound assignment (like +=)
      out "\$$lhs= $rhs;\n";  
      $ntok = 1;
   }
   elsif ($tok eq ')' && $g_unterminated_backtick) {
      out '`';
      $g_unterminated_backtick = 0;
      dec_indent();
   }
   elsif ($tok eq ';') {
      out "\n";
      $ntok = 1;
   }
   elsif ($tok =~ /^#/ && App::sh2p::Utils::new_line()) {
      $ntok = 1;
      out $tok;
   }
   elsif ($tok =~ /\`\s*(.*)\s*\`(.*)/) {
      my $cmd  = $1;
      my $rest = $2;
      my @cmd = split (/\s+/, $cmd);
      my @perlbi;
      
      if (@perlbi = App::sh2p::Parser::get_perl_builtin($cmd[0])) {
          # Do my best to trap unnecessary child processes
          out "\n";    # For tidy messages
          &{$perlbi[0]}(@cmd,$rest);
      }
      else {
          out " $tok ";
      }
      $ntok = 1;
   }
   elsif (substr($tok,0,1) eq '"') {
      interpolation($tok);
      $ntok = 1;
   }
   else {
      $ntok = 1;
      out " $tok ";
   }
   
   return $ntok;
}

############################################################################
# simplistic - should not split around whitespace
sub interpolation {
   my ($string) = @_;
   my $pos = 0;

   # Allow backticks 
   while ($string =~ /(.*?)(\$\(?\w+\)?)/g) {
       out $1;
       my $var = $2;
       Handle_variable($var);
       $pos = pos($string);
   }
   
   out substr($string, $pos);
   
}

############################################################################

sub Handle_2char_qx {
   
   my $ntok;
   my ($tok) = @_;
   my @perlbi;
   
   # Simple case first
   if ($tok =~ /^\$\((.*)\)(.*)$/) {
      my $cmd  = $1;
      my $rest = $2;
      my @cmd = split (/\s+/, $cmd);
      
      if (@perlbi = App::sh2p::Parser::get_perl_builtin($cmd[0])) {
          # Do my best to trap unnecessary child processes
          out "\n";    # For tidy messages
          &{$perlbi[0]}(@cmd,$rest);
      }
      else {
          iout "`$cmd`$rest";
      }
      
      $ntok = 1;
   }
   elsif ( substr($tok, 0, 2) eq '$(' ) {
      $tok =~ s/\$\(/`/; 
      $g_unterminated_backtick = 1;
      
      my @tokens = App::sh2p::Parser::tokenise ($tok);
      my @types  = App::sh2p::Parser::identify (1, @tokens); 
            
      App::sh2p::Parser::convert (@tokens, @types);
      
      inc_indent();
      $ntok = @_;
   }
   else {
      iout "@_";
      $ntok = @_;
   }
   
   return $ntok;
}

############################################################################
# Simplistic call to external program, should this be converted?

sub Handle_external {
      
   my $ntok = 1;
   my (@args) = @_;
   my $func = 'system';
   
   # Is final token a comment?
   my $last = '';

   if (substr($args[-1],0,1) eq '#') {
       $last = pop @args;
       $ntok++;
   }
      
   if ($g_unterminated_backtick) {
      if ($args[-1] eq ')') {
         $args[-1] = '`';
         $g_unterminated_backtick = 0; 
         iout "@args $last";
         dec_indent();
      }
      else {
         iout "@args $last";
      }
   }
   else {
      my @perlbi;
      my $user_function = 0;
      
      #pipes?

      if ( grep /\|/, @args) {
          $ntok = App::sh2p::Parser::analyse_pipeline (@args);
          return $ntok;
      }
      
      # If a user function, then call it as a subroutine
      if (is_user_function($args[0])) {
         $func = shift @args;
         $user_function = 1;
      }
      elsif (@perlbi = App::sh2p::Parser::get_perl_builtin($args[0])) {
         # Do my best to trap unnecessary child processes
         $ntok = &{$perlbi[0]}(@_);
         return $ntok;
      }
      
      if ($args[0] eq BREAK) {
          my @caller = caller();
          print STDERR "@caller\n";
          error_out ("Invalid BREAK in Handle_external");
      }
     
      my $semi = '';
      $semi = ';' if query_semi_colon();
      
      # Parse arguments
      if ( $user_function ) {
          for (my $i; $i < @args; $i++) {         
              $ntok++;
              # Escape embedded quotes
              $args[$i] =~ s/\"/\\\"/g;
              #"help syntax highlighter
              $args[$i] = "\"$args[$i]\"";
              $args[$i] .= ',' if $i < $#args;
          } 
          
          iout "$func (";
	  interpolation ("@args");
	  out ")$semi $last";

      }
      else {
          for my $arg (@args) {           
              $ntok++;
              # Escape embedded quotes
              $arg =~ s/\"/\\\"/g;
              #"help syntax highlighter
          }
          
          iout "$func (\"";
	  interpolation ("@args");
          out "\")$semi $last";
      }
      
      
      iout "\n" if query_semi_colon();
   }
   
   #local $" = '|';
   #print STDERR "external: $ntok<@args>\n";
   
   return $ntok;
}

##############################################################

sub Handle_Glob {

   my (@tokens) = @_;
   my $glob_check = '[*\[\]?]';
   my $pattern;
   my $ntok = 0;
   
   for (@tokens) {
      if (/$glob_check/) {
         $pattern .= $_;
         $ntok++
      }
   }
   
   iout "glob(\"$pattern\")";
   
   return $ntok;
}

############################################################################

#sub Handle_here_doc {
#
#}

############################################################################

sub Handle_unknown {   

   out "\"$_[0]\"";
   
   return 1;
}

############################################################################

1;