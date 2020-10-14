#!/usr/bin/perl
#
#

# read the states file


use strict ;
use Getopt::Std ;
our $opt_f = "" ;
our $opt_w = "" ;
our $opt_K = "proximity5" ;
our $opt_l = "-" ;
our $opt_d = "" ;
getopts('d:f:w:K:l:') ;

my @states = "" ;
my %cons ;
open (SF, "states.txt") || die "Can't open statest file\n" ;
while (<SF>) {
	chomp ;
	next unless /[A-Z]{2}/ ;
	push @states,$_ ;
}

my $lh ;
if ($opt_l eq "-") {
	$lh = *STDOUT ;
}
else {
	open ($lh, '>', "$opt_l") || die "Can't open $opt_l for writing:$!\n" ; 
}

print "Loaded states @states \n" ;

foreach my $st (@states) {
	my $estring ;
	my $recfile = $st . "record.csv" ;
	if ($opt_d ne "") {
		if (-d $opt_d) {
			$recfile = $opt_d . "/" . $recfile ; 
		}
		else {
			die "$opt_d is not a directory!\n" ;
		}
	}
	$estring = "./shp.pl -f $opt_f " ;
	if ($opt_w ne "") {
		$estring .= "-w $opt_w " ;
	}
	$estring .= "-r $recfile -s $st -K $opt_K 2>&1 |" ;
	print "$estring\n" ;
	#	system($estring) ;
	open (SH, "$estring") || die "Can't open $estring\n" ;
	while (<SH>) {
		chomp ;
		/^Consolidated:(.*)$/ && do {
			my $ln = $1 ;
			my @lflds = split /[=,\s]/, $ln;
			my %stateDetails ;
			$stateDetails{'towers'} = $lflds[3] ;
			$stateDetails{'towersDense'} = $lflds[8] ;
			$stateDetails{'Area'} = $lflds[11] ;
			$stateDetails{'CbGArea'} = $lflds[15] ;
			$cons{$st} = \%stateDetails ; 
		} ;
	}
	close(SH) ;
}

my $first = 1;
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
		print $lh "$det{$stdk} " ;
	}
	print $lh "\n" ;
}

sub HELP_MESSAGE {
print STDERR <<EOH
Usage: $0 -f inputshpfile -K <default clustering> -w <whitelist file> 
EOH
;
}
