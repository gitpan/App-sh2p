package App::sh2p::Handlers;

use strict;

use App::sh2p::Parser;
use App::sh2p::Utils;
use App::sh2p::Here;

sub App::sh2p::Parser::convert (\@\@);
use constant (BREAK => 0x07);

our $VERSION = '0.02';

my $g_unterminated_backtick = 0;

#  For use by App::sh2p only
############################################################################

sub Handle_assignment {
   # Currently does not handle arrays
   
   my $ntok = 1;
   my ($in, @rest)  = @_;
   
   #print STDERR "Handle_assignment: <$in>\n";
   
   $in =~ /^(\w+)=?(.*)$/;
   my $lhs = $1;
   my $rhs = $2;
   
   if (defined get_special_var($lhs)) {
      set_special_var ($lhs, $rhs);
   }
   
   my $name = "\$$lhs";
   
   if (Register_variable ($name) ) {
       iout "my $name";
   }
   else {
       iout "$name";
   }
   
   if ( ! defined $rhs ) {
      out ';';
      if ($ntok == @_) {
          out "\n";
      }
         
      return $ntok;
   }
   else {
      out ' = ';
   }
 
   my $isa_int = 0;
   if (get_variable_type($name) eq 'int') {
      $isa_int = 1;
   }
   
   if ( $rhs eq '' ) {
      if ($isa_int) {
         out 0
      }
      else {
         out '""'
      }
   }
   elsif ($rhs =~ /^\d+$/) {
      out $rhs
   }
   else {
      # Process the rhs
      if ($isa_int) {
         out "int(";
      }
      
      for my $tok (@rest) {
          last if substr($tok,0,1) eq '#';
          $rhs .= "$tok ";
          $ntok++;
      }
      
      no_semi_colon();
      my @tokens = App::sh2p::Parser::tokenise ($rhs);
      my @types  = App::sh2p::Parser::identify (1, @tokens); 
      
      # Avoid recursion
      die "Nested assignment $in" if $types[0] eq 'ASSIGNMENT';
      
      App::sh2p::Parser::convert (@tokens, @types);
      reset_semi_colon();
      
      if ($isa_int) {
         out ")";
      }

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
      
   if (Register_variable ($arr, '@') ) {
          iout "my \@$arr;\n";
   }

   # The shell allows a variable index without a '$'
   if ($idx =~ /^[[:alpha:]_]\w+/)  {  # No '$' (count + 1)
      $idx = "\$$idx";   
   }
   
   iout "\$$arr\[$idx\] = ";
      
   if ( !defined $rhs ) {
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

sub Handle_open_redirection {
    my ($type, $filename) = @_;
    
    # print STDERR "Handle_open_redirection: <$type> <$filename>\n";
    out ("\n");   
    iout ("open(my \$sh2p_handle,'$type',\"$filename\") or\n");
    iout ("     die \"Unable to open $filename: \$!\";\n");
    
}

############################################################################

sub Handle_close_redirection {
   
    iout ("close(\$sh2p_handle);\n");
    iout ("undef \$sh2p_handle;\n\n");
    
}

############################################################################

sub Handle_variable {
   my $token = shift;
   my $new_token;
   
   #print STDERR "Handle_variable: <$token>\n";
   #my @caller = caller();
   #print STDERR "Called from @caller\n";
   
   # Check for specials
   if ($new_token = get_special_var($token)) {
      $token = $new_token;
   }
   elsif ( $token =~ s/^\$#(\w+)/\$$1/ ) {
        out "length($token)";
        return 1;
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

sub Handle_expansion {
    my ($token) = @_;
    my $ntok;
    
    #   print STDERR "Handle_expansion: <$token>\n";
    #   my @caller = caller();
    #   print STDERR "Called from @caller\n";

    # Strip out the braces
    $token =~ s/\$\{(.*?)\}(.*?)/\$$1/;
    my $suffix = $2;
    
    if ( $token =~ /(\w+)([:?\-=+]{1,2})([^:?\-=+]+)/ ) {
        my $var    = '$'.$1;
        my $qual   = $2;
        my $extras = $3;
    
        # Remove the : 
        # Done this way in case further modification is required
        $qual =~ s/^://;
   
        if ($qual eq '?') {
            if (! $extras) {
                $extras = "'$var undef or not set'";
            }
            
            # $extras should already be quoted
            out ("print STDERR $extras,\"\\n\" if (! defined $var or ! $var);");
        }
        elsif ($qual eq '=') {
            #out ("$var = \"$extras\" if (! defined $var or ! $var);");
 	    out ("(defined $var or $var) || $var = ");
 	    my @tmp = ($extras);
 	    my @types  = App::sh2p::Parser::identify (1, @tmp);     
 	    App::sh2p::Parser::convert (@tmp, @types);
        }
        elsif ($qual eq '-') {
	    out ("(defined $var or $var) || ");
	    my @tmp = ($extras);
	    my @types  = App::sh2p::Parser::identify (1, @tmp);     
	    App::sh2p::Parser::convert (@tmp, @types);
        }
        elsif ($qual eq '+') {
	    out ("(! defined $var or ! $var) || ");
	    my @tmp = ($extras);
	    my @types  = App::sh2p::Parser::identify (1, @tmp);     
	    App::sh2p::Parser::convert (@tmp, @types);
  	}
        else {
            error_out ("Pattern $qual not currently supported");
            out ($token);
        }
        $ntok = 1;
    }    
    elsif ( $token =~ s/^\$#(.+)/\$$1/ ) {
        out "length($token)";
        $ntok = 1;
    }
    elsif ($token =~ /^(\$\w+)([%#]{1,2})(.*)/) {
        my $var     = $1;
        my $mod     = $2;
        my $pattern = $3;
        
        #print STDERR "Expansion 3: var: <$var> mod: <$mod> pattern: <$pattern>\n";
        
        if ($mod eq '#')  {  # delete the shortest on the left
            $pattern = App::sh2p::Compound::glob2pat($pattern,1,1);
            out "($var =~ /^(?:$pattern)+?(.*)/)[0]";
        }
        elsif ($mod eq '##') {  # delete the longest on the left
            $pattern = App::sh2p::Compound::glob2pat($pattern,1,0);
            out "($var =~ /^(?:$pattern)+(.*)/)[0]";    
        }
        if ($mod eq '%')  {  # delete the shortest on the right
            $pattern = App::sh2p::Compound::glob2pat($pattern,1,1);
            out "($var =~ /^(.*)(?:$pattern)+?\$/)[0]";
        }
        elsif ($mod eq '%%') {  # delete the longest on the right
            $pattern = App::sh2p::Compound::glob2pat($pattern,1,0);
            out "($var =~ /^(.*?)$pattern\$/)[0]";    
        }
        
        $ntok = 1;
    }
    else {     
        $ntok = Handle_variable($token);
    }
    
    if ($suffix) {
        out '.';
        my @tokens = App::sh2p::Parser::tokenise ($suffix);
        my @types  = App::sh2p::Parser::identify (1, @tokens);
   
        App::sh2p::Handlers::no_semi_colon();
        App::sh2p::Parser::convert (@tokens, @types);
        App::sh2p::Handlers::reset_semi_colon();
    }
    
    # Suffix was in the same token
    return $ntok;
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
      $ntok = 1;       # 0.03 added
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
      
      #print STDERR "Handle_delimiter <$tok>\n";
      
      if (@perlbi = App::sh2p::Parser::get_perl_builtin($cmd[0])) {
          
          # Do my best to trap unnecessary child processes
          out "\n" if query_semi_colon();    # For tidy messages
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

sub interpolation {
   my ($string) = @_;
   my $first = 1;
   my $delimiter = '';
   
   # strip out leading & trailing quotes
   $string =~ s/^\"(.*)\"$/$1/;
   
   # Insert leading quote to balence end
   # Why?  Because the string might not be quoted 
   out ('"');
   
   my @chars = split '', $string;
   
   # We need "". for print statement
   
   for (my $i = 0; $i < @chars; $i++) {
   
       if ($chars[$i] eq '\\') {   # esc
           out $chars[$i];
           $i++;
           out $chars[$i];
           $first = 0;
       }
       elsif ($chars[$i] eq '`') {
           out '".';
           $delimiter = '`';
           
           my $cmd = $chars[$i];
           $i++;
           
           while ($i < @chars) {
               $cmd .= $chars[$i];
               $i++;
               last if ($chars[$i] eq $delimiter);
           }

           Handle_delimiter ($cmd);
           out '."' if $i < (@chars-1);
       }
       elsif ($chars[$i] eq '$') {
           my $token = $chars[$i];
           $i++;
           
           if ($chars[$i] eq '(') {
               out '".';
               $delimiter = ')';
               while ($i < @chars) {
                   $token .= $chars[$i];
                   $i++;
                   if ($chars[$i] eq $delimiter) {
                       $token .= $chars[$i];
                       last
                   }
               }
               Handle_2char_qx ($token);
               out '."' if $i < (@chars-1);
           }
           elsif ($chars[$i] eq '{') {
               out '".';
               $delimiter = '}';
               while ($i < @chars) {
                   $token .= $chars[$i];
                   $i++;
                   if ($chars[$i] eq '}') {
                       $token .= $chars[$i];
                       last
                   }
               }
               Handle_expansion ($token);
               out '."' if $i < (@chars-1);
           }
           else {
               $delimiter = '';
               while ($i < @chars) {
                   $token .= $chars[$i];                 
                   last if ($chars[$i] !~ /[a-z0-9\#\[\]\@\*]/i);
                   $i++;
               }
               
               # Remove trailing whitespace, then put it back
               my $whitespace = '';
               
               if ($token =~ s/(\s+)$//) {
                   $whitespace = $1;
               }
               
               out '".' if ! can_var_interpolate($token);
               
               Handle_variable ($token);
               
               out '."'if ! can_var_interpolate($token);
               
               out $whitespace if ($whitespace);
           }
       }
       else {
           $delimiter = '';
           out $chars[$i];
       }
   }
   
   if ($chars[-1] ne $delimiter) {
       out '"';
   }
   
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
          out "\n" if query_semi_colon();    # For tidy messages
          &{$perlbi[0]}(@cmd,$rest);
      }
      elsif (is_user_function($cmd[0])) {
          error_out "User function '$cmd[0]' called in back-ticks";
          iout "`$cmd`$rest";
      }
      else {
          iout "`$cmd`$rest";
      }
      
      $ntok = 1;
   }
   elsif ( substr($tok, 0, 2) eq '$(' ) {
      $tok =~ s/\$\(/`/;
      
      # This is the ONLY place this is set
      $g_unterminated_backtick = 1;   

      my @tokens = App::sh2p::Parser::tokenise ($tok);
      my @types  = App::sh2p::Parser::identify (1, @tokens); 
      
      #print_types_tokens (\@types,\@tokens);      
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
   
   #print STDERR "Handle_external: <@args>\n";
   if ($g_unterminated_backtick) {
   
      if ($args[-1] eq ')') {
         $args[-1] = '`';
         $g_unterminated_backtick = 0; 
            print STDERR "Handle_external: <@args>\n";
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
      
          iout "$func (";
          
          if (@args) {
              for (my $i = 0; $i < @args; $i++) {         
                  $ntok++;
                  # Escape embedded quotes
                  $args[$i] =~ s/\"/\\\"/g;
                  #"help syntax highlighter
                  $args[$i] = "\"$args[$i]\"";
                  $args[$i] .= ',' if $i < $#args;
              } 
            
	      interpolation ("@args");
	  }
	  
	  out ")$semi $last";

      }
      else {
          for my $arg (@args) {           
              $ntok++;
              # Escape embedded quotes
              $arg =~ s/\"/\\\"/g;
              #"help syntax highlighter
          }
          
          # interpolation adds quotes
          iout "$func (";
	  interpolation ("@args");
          out ")$semi $last";
      }
      
      # Added 0.03
      if ($func eq 'system') {
          my $context = App::sh2p::Compound::get_context();
          if ($context eq 'if' || $context eq 'while') {
              out 'eq 0';
          }
          elsif ($context eq 'until') {
              out 'ne 0';
          }
      }
      
      out "\n" if query_semi_colon();
   }
   
   #local $" = '|';
   #print STDERR "external: $ntok<@args>\n";
   
   return $ntok;
}

##############################################################

sub Handle_Glob {

   my (@tokens) = @_;
   my $ntok = @tokens;
   
   local $" = '';
   iout "(glob(\"@tokens\"))";
   
   return $ntok;
}

############################################################################

sub Handle_unknown {   

   my ($token) = @_;

   if ($token =~ /^[-+]?\d+$/) {
       out "$token";
   }
   else {
       out "\"$token\"";
   }
   
   return 1;
}

############################################################################

1;
