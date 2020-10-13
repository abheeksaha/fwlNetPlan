#!/usr/bin/perl
package terraindB;

require Exporter ;
use strict;
use Data::Dumper ;
$Data::Dumper::Indent = 1;

our @ISA = qw(Exporter);
our @EXPORT = qw(getTerrainHgtProfile);
sub getTerrainCodeHgtProfile{
	my $lat = shift ;
	my $long= shift ;
	my $code ;
	my %hgtfiles ;
	my $fname = constructFileName($lat,$long) ;
	if (not defined $hgtfiles{$fname}) {
		my %bfContainer ; 
		if (!fileInit($fname,\%bfContainer)) {
				return 9999;
		}
		$bilfiles{$fname} = \%bfContainer ;
	}
	my $srtmData = readNLCDData($bilfiles{$fname},$lat,$long) ;
	return $srtmData ;
}

sub constructFileName {
	my $lat = shift ;
	my $long = shift ;
	my ($bdx,$bdy) ;
	#print "Longitude: $long, Latitude:$lat\n" ;
	die unless $long < 0 && $lat > 0 ;
	$bdx = int($lat) ;
	$bdy = int(-$long + 0.5) ;
	my $fname = sprintf( "N%2dW%2d" , $bdy,$bdx) ;
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
	my $xoffset = ($long - int($long))/3601 ;
	my $yoffset = ($lat - int($lat))/3601 ;
	#print "$xoffset,$yoffset for $lat,$long\n" ;
	my $offset = $yoffset*3601 ;
	my ($raw,$alt,$dh) ;
	$dh = ${$$fileContainer{'fh'}} ;
	seek $dh,$offset,0 ;
	my $success = read $dh, $raw, 2 ;
	die "Couldn't read binary file:$!\n" unless defined $success ;
	return $raw;
}
