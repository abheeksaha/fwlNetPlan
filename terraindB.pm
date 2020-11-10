#!/usr/bin/perl
package terraindB;

require Exporter ;
use strict;
use Data::Dumper ;
$Data::Dumper::Indent = 1;

our @ISA = qw(Exporter);
our @EXPORT = qw(getTerrainHgtProfile);
sub getTerrainHgtProfile{
	my $poly = shift ;
	my $npts = shift ;
	my @bpoints = $poly->points() ;
	my $tp = @bpoints ;
	my ($xrand,$yrand,$arand) ;
	my (@pts,@codes) ;
	my %hgtfiles ;
	my @hgts;
	my ($avg,$stddvn) ;
	$avg = $stddvn = 0;
	print "samplehistogram: npts=$npts, vertices=$tp:" ;
	for (my $i = 0; $i<$npts; $i++) {
		$xrand = rand($tp) ;
		$yrand = rand($tp) ;
		$arand = rand() ;
		my ($pt1,$pt2,$lat,$long) ;
		$pt1 = $bpoints[$xrand] ;
		$pt2 = $bpoints[$yrand] ;
		$long = $$pt1[0]*$arand + $$pt2[0]*(1 - $arand) ;
		$lat = $$pt1[1]*$arand + $$pt2[1]*(1 - $arand) ;
		#printf "%.4g,%.4g ",$rp[0],$rp[1] ;
		my $fname = constructHgtFileName($lat,$long) ;
		if (not defined $hgtfiles{$fname}) {
			my %bfContainer ; 
			if ($hgtfiles{$fname} == -1 || !fileInit($fname,\%bfContainer)) {
				$hgtfiles{$fname} = -1 ;
				return 9999;
			}
			$hgtfiles{$fname} = \%bfContainer ;
		}
		my $srtmData = readSrtmData($hgtfiles{$fname},$lat,$long) ;
		push @hgts,$srtmData ;
		$avg += $srtmData ;
	}
	$avg /= $npts ;
	print "Average = $avg\n" ;
	{
		foreach my $ht (@hgts) {
			$stddvn += ($ht - $avg)*($ht - $avg) ;
		}
		$stddvn = sqrt($stddvn)/$npts ;
	}
	return $stddvn ;
}

sub constructHgtFileName {
	my $lat = shift ;
	my $long = shift ;
	my ($bdx,$bdy) ;
	#print "Longitude: $long, Latitude:$lat\n" ;
	die unless $long < 0 && $lat > 0 ;
	$bdx = int($lat) ;
	$bdy = int(-$long) + 1 ;
	my $fname = sprintf( "N%2dW%.3d" , $bdx,$bdy) ;
	#print "Directory $dname File $fname\n" ;
	return ($fname) ;
}

sub fileInit {
	my $fname = shift ;
	my $fileCont = shift ;
	my ($fhgtname) ;
	print "Init $fname\n" ;
	my $tDir ; 
	if (defined ($ENV{'SRTMHOME'}) ) {
		$tDir = $ENV{'SRTMHOME'} ;
	}
	else { 
		$tDir = "/home/ggne0015/src/hnsNetPlan/srtm/SRTM" ;
	}
	$fhgtname = $tDir . "/". $fname. ".hgt" ;
	unless (-e $fhgtname) { print "Couldn't find $fhgtname\n" ; return 0 ; }
	my $fbil ;
	open ($fbil, $fhgtname) || die "Can't open $fhgtname for reading:$!\n" ;
	binmode $fbil ;
	$$fileCont{'fh'} = \$fbil ;
	return 1 ;
}

#
# HGT files are arranged W to E, N to S
# The filename is the s/w corner. 
#
#
sub readSrtmData {
	my $fileContainer = shift ;
	my $lat = shift ;
	my $long = shift;
	my $wlong = $long ;
	if ($wlong < 0) { $wlong = -$long ; }
	my $xoffset = int((1 - ($wlong - int($wlong)))*3601) ;
	my $yoffset = int((int($lat) + 1 - $lat)*3601) ;
	my $offset = (($yoffset)*3601 + $xoffset)*2 ;
	#print "xoff=$xoffset,yoff=$yoffset for $lat,$long, offset=$offset\n" ;
	my ($raw1,$raw2,$alt,$dh) ;
	$dh = ${$$fileContainer{'fh'}} ;
	seek $dh,$offset,0 ;
	my $success = sysread $dh, $raw1, 2 ;
	die "Couldn't read binary file:$!\n" unless defined $success ;
	$raw2 = unpack("n",$raw1) ;
	#print "raw1 = $raw1 raw2 = $raw2\n" ;
	return $raw2;
}

sub readSrtmDataFull {
	my $fileContainer = shift ;
	my $swLat = shift or 39;
	my $swLong = shift or -106;
	my $bestval = -1 ;
	my $bestoffset = 0 ;
	my $dh = ${$$fileContainer{'fh'}} ;
	my $offset = -2 ;
	for ($offset = 0; $offset < 3601*3601*2 ; $offset += 2) {
		seek $dh, $offset, 0;
		my $raw ;
		my $success = read $dh, $raw, 2 ;
		my $val = unpack("n",$raw) ;
		if ($val > $bestval) {
			$bestval = $val ;
			$bestoffset = $offset ;
			if ($val > 4300) { 
				my ($off,$xo,$yo,$lng,$lat);
				$off = $offset/2 ;
				$xo = $off%3600 ;
				$yo = int($off/3600) ;
				print "Offset = $offset val = $val, xo=$xo yo=$yo" ;
				$lat = ($swLat+1)-($yo/3601) ;
				$lng = ($swLong)+$xo/3601 ;
				print " Lat=$lat Long=$lng\n" ;
			}
		}
	}
	print "Best val $bestval at $bestoffset\n" ;
}
