#!/usr/bin/perl
#

use strict;
use Getopt::Std ;
use Math::Polygon;
use nlcd ;
use terraindB;

my @radius = (2.5,4,6) ;
our $opt_i = "";
our $opt_o = "" ;
getopts('i:o:');
open (IF,$opt_i) || die "Can't open $opt_i for reading\n" ;

my $milesperlat = 69 ;
my $milesperlong = 54.6 ; 
my $first = 1 ;
$|=1 ;
my $lh ;
if ($opt_o eq "") {
	$lh = *STDERR ;
}
else {
	open ($lh,">",$opt_o) || die "Can't open $opt_o for writing\n" ;
}
my $inf ;
while($inf = <IF>)
{
	chomp ($inf);
	my @entries = split/[, ]/, $inf ;
	my @opfields ;
	my $i ;
	my ($lat,$long) ;
	if ($first) { 
		foreach my $rad (@radius) {
			my $cstr = sprintf  "terrain code ($rad miles)" ;
			push @opfields,$cstr ;
			my $rstr = sprintf  "height variation ($rad miles)" ;
			push @opfields,$rstr ;
		}
		$first = 0;

	}
	else {
	for ($i=0; $i<@entries-1; $i++) {
		if ($entries[$i] =~ /[0-9.]+/ && $entries[$i+1] =~ /-[0-9.]+/) {
			$lat = $entries[$i] ;
			$long = $entries[$i+1] ;
			last ;
		}
	}
	if ($i == @entries-1) {
		#print $lh $inf ;
		next ;
	}
	print "Lat:$lat Long=$long\n" ;
	my (%terr, %ht);
	foreach my $rad (@radius) {
		($terr{$rad},$ht{$rad}) = getTerrainClass($lat,$long,$rad,4) ;
		my $ostrrad = sprintf "%.4g",$terr{$rad} ;
		my $ostrht = sprintf "%.4g",$ht{$rad} ;
		push @opfields,$ostrrad ;
		push @opfields,$ostrht ;
	}
	}
	foreach my $ent (@opfields) {
			print $lh "$ent," ;
	}
	print $lh "\n" ;
}

sub getTerrainClass{
	my $lat = shift;
	my $long = shift;
	my $rad = shift ;
	my $max = 4 ;
	my $xwidth = $rad/$milesperlong;
	my $ywidth = $rad/$milesperlat;
	my @pts ;
	for (my $i=0; $i<5; $i++) {
		my @pt ;
		if ($i ==0 || $i == 4) { $pt[1] = $lat + $ywidth/2; $pt[0] = $long + $xwidth/2 ; }
		elsif ($i ==1) { $pt[1] = $lat + $ywidth/2; $pt[0] = $long - $xwidth/2 ; }
		elsif ($i ==2) { $pt[1] = $lat - $ywidth/2; $pt[0] = $long + $xwidth/2 ; }
		elsif ($i ==3) { $pt[1] = $lat - $ywidth/2; $pt[0] = $long - $xwidth/2 ; }
		push @pts,\@pt ;
	}
	my $poly = Math::Polygon->new(@pts) ;
	printf "Polygon of area %.4g, %d points\n", $poly->area, $poly->nrPoints ;
	my %histogram ;
	my $npts = int($poly->area()*$milesperlat*$milesperlong)+1 ;
	my $spts = $npts*100 ;
	if ($spts > 100) { $spts = 100 ; }
	sampleHistogram($poly,$spts,\%histogram) ;
	my $tcode = getTerrainCodeFromHistogram(\%histogram,$max); 
	$tcode = int($tcode+1) ;
	my $htvar = getTerrainHgtProfile($poly,$spts) ;
	return ($tcode,$htvar) ;
}


