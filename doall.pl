#!/usr/bin/perl
#

use strict;
use Getopt::Std;


our $opt_h ;
our $opt_d = "." ;
our $opt_D = "processed/" ;
our $opt_w = "" ;
our $opt_K = "proximity3.5" ;
our $opt_C = "" ;
getopt('d:D:hw:K:C:') ;
if ($opt_h) {
	die <<EOH
	Usage: doall.pl -d <directory to read kmz files from> -D <directory to write processed files to> -K <default clustering> -C <directory of cluster files> -w <whitelist file>
EOH
;
exit(1) ;
}
my @clusterfiles ;
opendir(DIR, $opt_d) || die "Can't open directory $opt_d:$!\n" ;
if (-d $opt_C) {
	opendir (CDIR, $opt_C) || die "Can't open directory $opt_D for cluster files:$!\n" ; 
	while (my $rname = readdir(CDIR) ) {
		next unless ($rname =~ /([A-Z]){2}[a-z]+.csv/) ;
		push @clusterfiles,$rname ;
	}
}

while (my $fname = readdir(DIR)) {
	next unless ($fname =~ m@^([A-Z]+).kmz$@);
	print "Processing $fname\n" ;
	my $state = $1 ;
	my $ofile = $opt_D . $1."mod.kmz" ;
	my $rfile = $opt_D . $1."report.csv" ;
	my $tfile = $opt_D . $1."terrain.csv" ;
	my $cfile = $1 . "cluster.csv" ;
	my $wfile ;
	if ($opt_w eq "") { $wfile = $opt_d . "CBG_Short_List_v1.csv" ; }
	elsif (-e $opt_w) { $wfile = $opt_w ; }
	else { die "Provided whitelist file $opt_w doesn't exist\n" ; }

	#print "Executing $fname...$ofile\n" ;
	my $estring = "" ;
	foreach my $cf (@clusterfiles) {
		if ($cfile eq $cf) {
			my $fcf = $opt_C . "/" . $cf ;
			$estring = "./kmz.pl -f ". $opt_d . $fname . " -k " . $ofile . " -r " . $rfile . " -K $fcf";
		}
	}
	if ($estring eq "") {
		$estring = "./kmz.pl -f ". $opt_d . $fname . " -k " . $ofile . " -r " . $rfile . " -K $opt_K";
	}
	$estring .= " -w " . $wfile . " 2>&1 |";
	print "$estring\n" ;
	#	system($estring) ;
		open (SH, "$estring") || die "Can't open $estring\n" ;
		while (<SH>) {
			chomp ;
			if (/Couldn't find/) { print "$_\n" ; }
	#	/State.*xmin=([-0-9.]+).*xmax=([-0-9.]+).*ymin=([-0-9.]+).*ymax=([-0-9.]+)/ &&
	#		do {
	#			if ($opt_b) { print FH "$state,$1,$2,$3,$4\n" ;  }
	#			{ print "$state,$1,$2,$3,$4\n" ;  }
	#		} ;
		}
	close(SH) ;
}
close (FH) ;
