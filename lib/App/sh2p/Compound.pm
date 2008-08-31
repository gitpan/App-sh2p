package App::sh2p::Compound;

use strict;
use App::sh2p::Parser;
use App::sh2p::Utils;
use App::sh2p::Handlers;

sub App::sh2p::Parser::convert (\@\@);
use constant (BREAK => '@');

our $VERSION = '0.02';

my $g_not = 0;

#####################################################
              #  shell   perl
my %convert = ( '=='  => 'eq',
                '='   => 'eq',
                '!='  => 'ne',
                '<'   => 'lt',
                '>'   => 'gt',
                '<='  => 'le',
                '>='  => 'ge',
                '-eq' => '==',
                '-ne' => '!=',
                '-lt' => '<',
                '-gt' => '>',
                '-ge' => '>=',
                '-le' => '<=',
                '-nt'=> undef,
                '-ot'=> undef,
                '-ef'=> undef,
                '-n' => '',       # No value required
                '-z' => '!',
                '-a' => '-e',     # see %sh_convert
                '-h' => '-l',
                '-o' => undef,    # shell option, but see %sh_convert
                '-O' => '-o',     # confused?
                '-G' => undef,    # owned by egid
                '-L' => '-l',
                '-N' => undef);   # modified since last read);

# Many options are the same as the Perl functions, but not all
# Bourne shell syntax overlaps
my %sh_convert = ('-o' => 'or',
                  '-a' => 'and');
                     
#####################################################
# ((
sub arith {

   my ($statement) = @_;  
   
   # First 2 chars passed should be (( or $((
   $statement =~ s/^\$?\(\(//;
   # Last 2 chars passed should be ))
   $statement =~ s/\)\)$//;
   
   my $out = '( ';
   my @tokens = App::sh2p::Parser::tokenise ($statement);

   my $pattern = '==|>=|<=|\/=|%=|\+=|-=|\*=|=|>|<|!=|\+|-|\*|\/|%';

   for my $token (@tokens) {
      
      # Further tokenise
      
      $token =~ s/($pattern)/$1 /;
      
      for my $subtok (split (/ /, $token)) {
      
          if ($subtok =~ /^[_A-Za-z]/) {
              # Must be a variable!
              $subtok = "\$$subtok";
          }
          
          $out .= "$subtok "
      }
      
   }
  
   out "$out )";
   
   return 1;
}

#####################################################
# [[
sub ksh_test {

   my ($statement) = @_;   
   
   # First 2 chars passed should be [[
   $statement =~ s/^\[\[//;
   # Last 2 chars passed should be ]]
   $statement =~ s/\]\]$//;
   
   # extglob
   my $specials = '\@|\+|\?|\*|\!';
   
   my @tokens = App::sh2p::Parser::tokenise ($statement);
   my @types  = App::sh2p::Parser::identify (1, @tokens);
   
   my $index = 0;
   for my $token (@tokens) {
      if (exists $convert{$token}) {
         $token = $convert{$token};
         
         $types[$index] = [('OPERATOR', \&App::sh2p::Operators::boolean)];
      } 
      elsif (substr($token,0,1) eq '-') {
          $types[$index] = [('OPERATOR', \&App::sh2p::Operators::boolean)];
      }
      else {
         # look for shell pattern matching constructs (extglob)
         if ($token =~ /($specials)\(/) {
	     error_out ("Unable to convert shell pattern matching <$token>");
	     $types[$index] = [('OPERATOR', \&App::sh2p::Operators::no_change)];
	 }
	 elsif ($token eq '!') {
	     $g_not = 1;
	 }
      }
      $index++;
   }

   if ($g_not) {
      out '( ! ';
      $g_not = 0;
   }
   else {
      out '( ';   
   }
   
   App::sh2p::Parser::convert (@tokens, @types);
   out ' )';
   
   return  1;
}

#####################################################
# Not strictly a compound statement, but near enough
# This is called for test and [
sub sh_test {
 
   my $ntok = 1;
   my ($statement, @rest) = @_;  
   
   # First char/s passed should be [ or test
   $statement =~ s/^\[|^test//;
   
   if (@rest) {
      my $i;
      
      for ($i = 0; $i < @rest; $i++) {
          
          last if $rest[$i] eq BREAK || $rest[$i] eq ';';
      }
      
      if ( $i ) {      
          $statement = join (' ', splice(@rest,0,$i));
          $ntok += $i;
      }
   }

   # Last char passed may be ]
   $statement =~ s/\]$//;
   
   # glob
   my $specials = '\[|\*|\?';
   
   my @tokens = App::sh2p::Parser::tokenise ($statement);
   my @types  = App::sh2p::Parser::identify (1, @tokens);
      
   my $index = 0;
   for my $token (@tokens) {
      
      if (exists $sh_convert{$token}) {
         $token = $sh_convert{$token};
         $types[$index] = [('OPERATOR', \&App::sh2p::Operators::boolean)];
      }       
      elsif (exists $convert{$token}) {   # ksh options
         $token = $convert{$token};
         $types[$index] = [('OPERATOR', \&App::sh2p::Operators::boolean)];
      } 
      elsif (substr($token,0,1) eq '-') {
          $types[$index] = [('OPERATOR', \&App::sh2p::Operators::boolean)];
      }
      else {
         # TODO look for glob constructs  
         if ($token =~ /($specials)\(/) {
	     error_out ("Unable to convert glob constructs <$token>");
	     $types[$index] = [('OPERATOR', \&App::sh2p::Operators::no_change)];
	 }
	 elsif ($token eq '!') {
	     $g_not = 1;
	 }
      }
      $index++;
   }
  
   if ($g_not) {
       out '( ! ';
       $g_not = 0;
   }
   else {
       out '( ';   
   }
   
   App::sh2p::Parser::convert (@tokens, @types);
   out ' )';
      
   return  $ntok;
}

#####################################################

sub Handle_if {

   my ($cmd, @statements) = @_;
   my $ntok = 1;
   
   # First token is 'if'
   iout "$cmd ";
   
   # 2nd command?
   if (@statements) {
       $ntok += process_second_statement(1, @statements);
   }
   
   return $ntok;
}

#####################################################

sub Handle_fi {

   dec_indent();
   dec_block_level();
   out "\n";
   iout "}\n";
   
   return 1;
}

#####################################################

sub Handle_not {
    $g_not = 1;
    return 1;
}

#####################################################

sub Handle_then {
   my ($cmd, @statements) = @_;
   my $ntok = 1;
  
   iout "{\n";
   inc_indent();
   inc_block_level();
      
   # 2nd command?
   if (@statements) {
       $ntok += process_second_statement(0, @statements);
   } 
      
   return $ntok;
}

#####################################################

sub Handle_else {
   my ($cmd, @statements) = @_;
   my $ntok = 1;

   dec_indent();
   dec_block_level();
   out "\n";
   iout "}\n";
   iout "else {\n";
   inc_indent();
   inc_block_level();

   # 2nd command?
   if (@statements) {
       $ntok += process_second_statement(0, @statements);
   }
   
   return $ntok;
}

#####################################################

sub Handle_elif {
   my ($cmd, @statements) = @_;
   my $ntok = 1;

   dec_indent(); 
   dec_block_level();
   out "\n";
   iout "}\n";
   iout 'elsif ';

   # 2nd command?
   if (@statements) {
       $ntok += process_second_statement(1, @statements);
   }

   return $ntok;
}

#####################################################

sub Handle_for {

   # Format: for var in list
   my ($cmd, $var, $in, @list) = @_;
   
   my $ntok = @_;
   if (substr(0,1,$list[-1]) eq '#') {
      $ntok--;
      pop @list;
   }
   
   # Using first argument because this is also used for select (temp)
   error_out ("No conversion for $cmd, consider Shell::POSIX::select") if $cmd eq 'select';
   iout "$cmd my \$$var (";
   
   my @for_tokens;
   my $i;
   for (my $i=0; $i < @list; $i++) {
       last if $list[$i] eq 'do';
   }
   
   @for_tokens = splice (@list, 0, $i+1);
   
   # Often a variable to be converted to a list
   # Note: excludes @ and * which indicate an array
   if ($for_tokens[0] =~ /\$[A-Z0-9#{}\[\]]+/i) {
      my $IFS = App::sh2p::Utils::get_special_var('IFS');
      $IFS =~ s/^"(.*)"/$1/;
      out "split /$IFS/,$for_tokens[0]";
      shift @for_tokens;
   }
   
   if (@for_tokens) {
       my @types  = App::sh2p::Parser::identify (2, @for_tokens);
       App::sh2p::Parser::convert (@for_tokens, @types);
   }
   out ')';
   
   my @types  = App::sh2p::Parser::identify (2, @list);
   App::sh2p::Parser::convert (@list, @types); 

   return $ntok;
}

#####################################################

sub Handle_while {

   my ($cmd, @statements) = @_;
   my $ntok = 1;
   
   # First token is 'while'
   iout "$cmd ";
   
   # 2nd command?
   if (@statements) {
       $ntok += process_second_statement(1, @statements);
   }
   
   return $ntok;
}

#####################################################

sub Handle_until {

   my ($cmd, @statements) = @_;
   my $ntok = 1;
   
   # First token is 'until'
   iout "$cmd ";
   
   # 2nd command?
   if (@statements) {
       $ntok += process_second_statement(1, @statements);
   }
   
   return $ntok;
}


#####################################################

sub Ignore {
   return 1;
}

#####################################################

sub Handle_done {

   dec_indent();
   dec_block_level();
   out "\n";
   iout "}\n";
   
   return 1;
}


#####################################################

sub Handle_do {

   iout "{\n";
   inc_indent();
   inc_block_level();
   
   return 1;
}

#####################################################

sub Handle_function {

   # Format: function name {
   
   my (undef, $name) = @_;
   
   out "sub $name ";
   
   set_user_function($name);
   
   
   return 2;
}

#####################################################

sub open_brace {

   iout "{\n";
   inc_indent();

   mark_function();
   inc_block_level();
   
   return 1;
}

#####################################################

sub close_brace {

   dec_indent();
   iout "\n}\n";

   unmark_function();
   dec_block_level();

   return 1;
}

#####################################################
# Called by if, then, else, elif, while, until
# First parameter set to true by if, elif, while, until

sub process_second_statement {
   my ($cmd, @statements) = @_;
   my $statement;
   my $i;
   my $paren = 0;   
   
   for ($i = 0; $i < @statements; $i++) {
       
       last if $statements[$i] eq BREAK || $statements[$i] eq ';';
   }
   
   return 0 unless $i;
   
   $statement = join (' ', splice(@statements,0,$i));
   
   my @tokens = App::sh2p::Parser::tokenise ($statement);
   my @types  = App::sh2p::Parser::identify (0, @tokens);

   #print_types_tokens (@types, @tokens);

   if ($cmd && $tokens[0] ne 'test' &&
      ($types[0][0] eq 'EXTERNAL' || 
       $types[0][0] eq 'BUILTIN'  ||
       $types[0][0] eq 'PERL_BUILTIN')
      ) {
       $paren = 1;
       out '('
   }
   
   App::sh2p::Handlers::no_semi_colon();
   App::sh2p::Parser::convert (@tokens, @types);
   App::sh2p::Handlers::reset_semi_colon();

   if ($paren) {
       out ')'
   }

   return $i;
}

#####################################################

1;