#!/usr/bin/perl
#

use strict ;
while(<>) {
	/CBG/ && do { print ; next ; } ;
	chomp ;
	my @records = split /,/ ;
	my $numr = @records ;
	my $cbglist = $records[$numr-2] ;
	my $fidlist = $records[$numr-1] ;
	my @cbgs = split /:/, $cbglist ;
	my @fids = split /:/, $fidlist ;
	if (@fids != @cbgs) { 
		die "Fids dont match with cbgs, @fids,@cbgs\n" ;
	}
	my $i = 0 ;
	for ($i=0; $i<@cbgs;$i++) {
		for (my $k=0; $k<$numr-2 ; $k++) {
			print "$records[$k]," ;
		}
		print "$cbgs[$i],$fids[$i]\n" ;
	}
}
