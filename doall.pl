#!/usr/bin/perl
#

use strict;
use Getopt::Std;


our $opt_h ;
our $opt_d = "." ;
our $opt_D = "processed/" ;
our $opt_w = "" ;
our $opt_K = "proximity3.5" ;
our $opt_C = "";
our $opt_c = "";
our $opt_l = "doall.log" ;
my %cons ;
$Getopt::Std::STD_HELP_VERSION = 1 ;
getopts('d:D:hw:K:c:C:l:') ;
if ($opt_h) {
print "Printing usage\n" ; 
	HELP_MESSAGE() ;
exit(1) ;
}
my $lh ;
if ($opt_l eq "-") {
	$lh = *STDOUT ;
}
else {
	if ($opt_d ne "" && (-d $opt_d))
	{
		$opt_l = $opt_d . "/" . $opt_l ;
	}
	open ($lh, '>', "$opt_l") || die "Can't open $opt_l for writing:$!\n" ; 
}
my @clusterfiles ;
opendir(DIR, $opt_d) || die "Can't open directory $opt_d:$!\n" ;
if (-d $opt_c) {
	opendir (CDIR, $opt_c) || die "Can't open directory $opt_D for cluster files:$!\n" ; 
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

	#print "Executing $fname...$ofile\n" ;
	my $estring = "" ;
	foreach my $cf (@clusterfiles) {
		if ($cfile eq $cf) {
			my $fcf = $opt_c . "/" . $cf ;
			$estring = "./kmz.pl -f ". $opt_d . $fname . " -k " . $ofile . " -r " . $rfile . " -K $fcf";
		}
	}
	if ($estring eq "") {
		$estring = "./kmz.pl -f ". $opt_d . $fname . " -k " . $ofile . " -r " . $rfile . " -K $opt_K";
	}
	if ($opt_C ne "" ) { $estring .= " -C $opt_C " ; }
	if ($opt_w ) {
		if ((-e $opt_w)) { $estring .= " -w " . $opt_w ; }
		else { die "$opt_w doesn't exist!\n" ; }
	}
	$estring .= " 2>&1 |";
	print "$estring\n" ;
	#	system($estring) ;
		open (SH, "$estring") || die "Can't open $estring\n" ;
		while (<SH>) {
			chomp ;
			/skipped/ && print "$_\n" ;
			/unassigned/i && print "$_\n" ;
			/Too many/ && print "$_\n" ;
			if (/Couldn't find/) { print "$_\n" ; }
			/^Consolidated:(.*)$/ && do {
				my $ln = $1 ;
				my @lflds = split /[=,\s]/, $ln;
				my %stateDetails ;
				$stateDetails{'towers'} = $lflds[3] ;
				$stateDetails{'towersDense'} = $lflds[8] ;
				$stateDetails{'Area'} = $lflds[11] ;
				$stateDetails{'CbGArea'} = $lflds[15] ;
				$cons{$state} = \%stateDetails ; 
			} ;

#		print "Consolidated: Towers(all coverage)=%d, Towers(64QAM and better)=%d, Area=%.6g, CBG Area=%.6g\n",
	#	/State.*xmin=([-0-9.]+).*xmax=([-0-9.]+).*ymin=([-0-9.]+).*ymax=([-0-9.]+)/ &&
	#		do {
	#			if ($opt_b) { print FH "$state,$1,$2,$3,$4\n" ;  }
	#			{ print "$state,$1,$2,$3,$4\n" ;  }
	#		} ;
		}
	close(SH) ;
}
close (FH) ;

my $first = 1;
my %tot ;
foreach my $st (sort keys %cons) {
	my %det = %{$cons{$st}} ;
	if ($first) {
		foreach my $tdk (sort keys %det) {
			print $lh "$tdk " ;
		}
		print $lh "\n" ;
		$first = 0;
	}
	print $lh "$st " ;
	foreach my $stdk (sort keys %det) {
		$tot{$stdk} += $det{$stdk} ;
		print $lh "$det{$stdk} " ;
	}
	print $lh "\n" ;
}
print "Total:" ;
foreach my $tdk (sort keys %tot) {
	print "$tdk -> $tot{$tdk} ";
}
print "\n" ;

sub HELP_MESSAGE {
print STDERR <<EOH
Usage: doall.pl -d <directory to read kmz files from> -D <directory to write processed files to> -K <default clustering> -c <directory of cluster files> -w <whitelist file> -l <logfile> -C (pass through to kmz.pl)
EOH
;
}
