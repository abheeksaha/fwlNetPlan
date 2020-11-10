#!/usr/bin/perl
package nlcd;

require Exporter ;
use Data::Dumper ;
use Math::Polygon ;
$Data::Dumper::Indent = 1;
use strict;

our @ISA = qw(Exporter);
our @EXPORT = qw(codePointList sampleHistogram getTerrainCodeFromHistogram );

sub sampleHistogram {
	my $poly = shift ;
	my $npts = shift ;
	my $hist = shift ;
	my @bpoints = $poly->points() ;
	my $tp = @bpoints ;
	my ($xrand,$yrand,$arand) ;
	my (@pts,@codes) ;
	print "samplehistogram: npts=$npts, vertices=$tp:" ;
	for (my $i = 0; $i<$npts; $i++) {
		$xrand = rand($tp) ;
		$yrand = rand($tp) ;
		$arand = rand() ;
		my ($pt1,$pt2,@rp) ;
		$pt1 = $bpoints[$xrand] ;
		$pt2 = $bpoints[$yrand] ;
		$rp[1] = $$pt1[0]*$arand + $$pt2[0]*(1 - $arand) ;
		$rp[0] = $$pt1[1]*$arand + $$pt2[1]*(1 - $arand) ;
		#printf "%.4g,%.4g ",$rp[0],$rp[1] ;
		push @pts,\@rp ;
	}
	print "\nsampleHistogram: Calling code point list\n" ;
	codePointList(\@pts,\@codes) ;

	for (my $j=0; $j<@codes;$j++) {
		$$hist{$codes[$j]}++ ;
	}
	for my $keyv (keys %$hist) {
		print "$keyv=>$$hist{$keyv} " ;
	}
	print "\n" ;
}

sub codePointList {
	my $pts = shift ;
	my $codes = shift ;
	my %bilfiles ;
	my $npts = 0;
	foreach my $pt (@$pts) {
		my $lat = $$pt[0] ;
		my $long = $$pt[1] ;
		my ($fname,$dname) = constructFileDirName($lat,$long) ;
		if (not defined $bilfiles{$fname}) {
			my %bfContainer ; 
			if (!fileInit($fname,$dname,\%bfContainer)) {
				push @$codes,9999;
				$bilfiles{$fname} = -1 ;
				next ;
			}
			#foreach my $bfckey (keys %bfContainer) {
			#	print "$bfckey => $bfContainer{$bfckey}\n" ;
			#}
			$bilfiles{$fname} = \%bfContainer ;
		}
		elsif ($bilfiles{$fname} == -1) {
			push @$codes,9999 ;
			next ;
		}
		if (!($npts++ % 100)) { print "." ; }
		my $nlcdData = readNLCDData($bilfiles{$fname},$lat,$long) ;
		#print "$lat,$long ==> $nlcdData\n" ;
		push @$codes,$nlcdData ;
	}
	print "\n" ;
}

#
# File name NLCD2016_N33W96 contains:
# y: 36 to 33
# x: -96 to -93 
#
sub constructFileDirName {
	my $lat = shift ;
	my $long = shift ;
	my ($bdx,$bdy) ;
	if ($long > 0 && $lat < 0 ) {
		die "Longitude: $long, Latitude:$lat\n" ;
	}

	$bdx = int($long/3) ; $bdy = int($lat/3) ;  
	$bdx = -3*($bdx-1) ; $bdy = 3*int($bdy) ;
	my $fname = sprintf( "NLCD2016_N%2dW%2d" , $bdy,$bdx) ;
	my $dname = sprintf( "NLCD2016_N%2dW%2d" , $bdy,$bdx) ;
	#print "Directory $dname File $fname\n" ;
	return ($fname,$dname) ;
}

sub fileInit {
	my $fname = shift ;
	my $dname = shift ;
	my $fileCont = shift ;
	my ($fhdrname,$fbilname) ;
	print "Init $fname\n" ;
	my $tDir ; 
	if (defined ($ENV{'NLCDHOME'}) ) {
		$tDir = $ENV{'NLCDHOME'} ;
	}
	else { 
		$tDir = "/home/ggne0015/src/hnsNetPlan/srtm/NLCD_2016" ;
	}
	$fhdrname = $tDir . "/" . $dname . "/" . $fname . ".hdr" ;
	$fbilname = $tDir . "/" . $dname . "/" . $fname . ".bil" ;
	unless (-e $fhdrname) { print "Couldn't find $fhdrname\n" ; return 0 ; }
	unless (-e $fbilname) { print "Couldn't find $fbilname\n" ; return 0 ; } 
	open (FH, $fhdrname) || die "Can't open $fhdrname for reading:$!\n" ;
	while (<FH>) {
		my @keyv = split(/\s+/) ;
		#print "$keyv[0] => $keyv[1]\n" ;
		$$fileCont{$keyv[0]} = $keyv[1] ; 
	}
	close (FH) ;
	my $fbil ;
	open ($fbil, $fbilname) || die "Can't open $fbilname for reading:$!\n" ;
	binmode $fbil ;
	$$fileCont{'fh'} = \$fbil ;
	return 1 ;
}

#
# File name NLCD2016_N33W96 contains:
# y: 36 to 33, decreasing
# x: -96 to -93 , increasing
# ulxmap: -96
# ulymap: 36
#
sub readNLCDData {
	my $fileContainer = shift ;
	my $lat = shift ;
	my $long = shift;
	my $xoffset = int(($long - $$fileContainer{'ULXMAP'})/($$fileContainer{'XDIM'})) ;
	my $yoffset = int(($$fileContainer{'ULYMAP'} - $lat)/($$fileContainer{'YDIM'})) ;
	#print "$xoffset,$yoffset for $lat,$long\n" ;
	my $offset = $yoffset*$$fileContainer{'TOTALROWBYTES'} + $xoffset ;
	my ($raw,$alt,$dh) ;
	$dh = ${$$fileContainer{'fh'}} ;
	seek $dh,$offset,0 ;
	my $success = read $dh, $raw, 1 ;
	die "Couldn't read binary file:$!\n" unless defined $success ;
	return ord($raw) ;
}
sub getTerrainCodeFromHistogram {
	my $hist = shift ;
	my $range = shift ;
	my ($forest,$urban,$wet,$good,$unk)  ;
	my ($total) ;
	my $ret ;
	print "getTerrainCode:" ;
	$forest = $$hist{41} + $$hist{42}+ $$hist{43} ;
	$urban = $$hist{22} + $$hist{23} + $$hist{24} ;
	$wet = $$hist{11} + $$hist{12} + $$hist{90} + $$hist{95} ;
	if (defined($$hist{9999})) { $unk = $$hist{9999} ; }
		else { $unk = 0; }
	$total = 0 ;
	for my $nlcd (keys %$hist) {
		print "$nlcd=>$$hist{$nlcd} " ;
		$total += $$hist{$nlcd} ;
	}
	print "forest = $forest, urban=$urban, wet = $wet " ;
	$ret = ($forest + $urban + $wet + ($unk/2))/$total ;
	print "ret=$ret unknown=$unk\n" ;
	if ($ret == 1) { return $range - 1 ; }
	return $ret*$range ;
}
