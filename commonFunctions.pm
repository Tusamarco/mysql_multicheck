#!/usr/bin/perl
package commonFunctions;

use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION);
$VERSION = 1.50;              # Or higher
@ISA = qw(Exporter);
@EXPORT = qw(big_sub make_bigint big_multiply big_add increment array_sum) ;

# ============================================================================
# Subtract two big integers as accurately as possible with reasonable effort.
# 
# ============================================================================
sub big_sub ($$) {
    
    my $left = shift;
    my $right = shift;
   # my $force = shift;
   
    if($left=~ m/.[ABCDF]/){
	$left = hex($left);
	return $left;
   }

    if($right=~ m/.[ABCDF]/){
	$right = hex($right);
	return $right;
   }
   
   if ( !defined $left  ) { $left = 0; }
   if ( !defined $right ) { $right = 0; }
   
   #return ()
    my $x = Math::BigInt->new($left);
    my $xint = $x->bsub($right);
    return $xint->{value}[0];
}

# ============================================================================
# Returns a bigint from two ulint or a single hex number.  
# ============================================================================
sub make_bigint ($$) {
   my $hi = shift;
   my $lo = shift;
   if($hi=~ m/.[ABCDF]/){
	$hi = hex($hi);
	return $hi;
   }
   
   
   if (defined $lo ) {
      # Assume it is a hex string representation.
      my $x = Math::BigInt->new($hi);
      my $xint = $x->as_number;
      return $xint->{value}[0];
   }
   else {
      $hi = $hi ? $hi : '0'; # Handle empty-string or whatnot
      $lo = $lo ? $lo : '0';
      return big_add(big_multiply($hi, 4294967296), $lo);
   }
}

# ============================================================================
# Multiply two big integers together as accurately as possible with reasonable
# effort. 
# ============================================================================
sub big_multiply ($$$) {
   my $left = shift;
   my $right = shift;
   my $force = shift;
   
    if($left=~ m/.[ABCDF]/){
	$left = hex($left);
	return $left;
   }

    if($right=~ m/.[ABCDF]/){
	$right = hex($right);
	return $right;
   }
   
   
   my $x = Math::BigInt->new($left);
   my $bx = $x->bmul($right);
   return $bx->{value}[0];
  
 
}
# ============================================================================
# Add two big integers together as accurately as possible with reasonable
# effort.  
# ============================================================================
sub big_add ($$$) {
    my $left = shift;
    my $right = shift;
    my $force = shift;
    
     if($left=~ m/.[ABCDF]/){
	$left = hex($left);
	return $left;
   }

    if($right=~ m/.[ABCDF]/){
	$right = hex($right);
	return $right;
   }
    
   if ( !defined $left )
      {
	 $left = 0;
    }
   if ( !defined $right) { $right = 0; }
  
    my $x = Math::BigInt->new($left);
    my $bx = $x->badd($right);
     return $bx->{value}[0];
 
   
 
}


# ============================================================================
# Safely increments a value that might be null.
# ============================================================================
sub increment(\%$$) {
   my $hash = shift;
   my $key = shift;
   my $howmuch = shift;
    
   if ( defined $hash->{$key}) {
      if ($hash->{$key} > 0)
      {
	my $value = int($hash->{$key});
	$hash->{$key} = ($value + $howmuch);
      }
      else
      {
	$hash->{$key} = ($howmuch);
      }
   }
   else
   {
	$hash->{$key} = $howmuch;

   }
   return $hash;
}

# ============================================================================
# Sum the content of the array assuming it is numeric 
# ============================================================================
sub array_sum(@){
    my @array = shift;
    my $acc = 0;
    foreach (@array){
      $acc += $_;
    }
    return $acc;
}


1;