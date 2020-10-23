#!/usr/bin/perl
package txtKML;

require Exporter ;
use strict;
use Geo::KML ;

our @ISA = qw(Exporter);
our @EXPORT = qw(loadKMLTxt) ; 

sub loadKMLTxt {
	my $fname = shift ;
	my $records = shift ;
	my $uniqNum = $$ ;
	open (F1, "$fname") || die "Can't open $fname for reading\n" ;
	my $oldirs = $/ ;
	undef $/ ;
	my $fdata = <F1> ;
	$/ = $oldirs ;
	$fdata =~ s/[\t\n]/ /gm ;
	my @placemarks = split /Placemark/,$fdata ;
	my $i;
	for ($i = 0 ; $i <@placemarks ; $i++) {
		next unless ($placemarks[$i] =~ /\d+/) ;
		my ($state,$county,$fip,$coordinates) = processPlacemark($placemarks[$i]) ;
		my %rec ;
		$rec{'county'} = $county ;
		$rec{'state'} = $state ;
		$rec{'coordinates'} = $coordinates ;
		$rec{'cbg'} = sprintf("%s%d",$county , $uniqNum) ; $uniqNum++ ;
		$rec{'fid'} = $fip ;
		push @$records,\%rec ;
	}
	my $npk = @$records ;
	print "$npk placemarks found\n" ;
}

sub processPlacemark{
	my $istr = shift ;
	my ($county,$st,$fips) ;
	my @pcoords ;
	if ($istr =~ m@<SimpleData name="NAME">([^<]+)<@) {$county = $1 ; $county =~ s/\s+/_/g ; }
	if ($istr =~ m@<SimpleData name="FIPS">([^<]+)<@) {$fips = $1 ; }
	if ($istr =~ m@<SimpleData name="STATE_NAME">([^<]+)<@) {$st = $1 ; }
	if ($istr =~ m@<outerBoundaryIs>\s+<LinearRing>\s+<coordinates>([^<]+)<@) {
		my $clist = $1 ;
		my @points = split / /,$clist ;
		foreach my $pt (@points) {
			my ($x,$y,$z)= split /,/,$pt;
			next unless ($x =~ /-[0-9.]+/ && $y =~ /[0-9.]+/) ;
			my @xy ;
			$xy[0] = $x ; $xy[1] = $y ;
			push @pcoords,\@xy ;
		}
	}
	return ($st,$county,$fips,\@pcoords) ;
}
1;

#>      <name>27077</name>      <styleUrl>#falseColor110</styleUrl>      <ExtendedData>       <SchemaData schemaUrl="#S_UScounties_SSSSS">        <SimpleData name="NAME">Lake of the Woods</SimpleData>        <SimpleData name="STATE_NAME">Minnesota</SimpleData>        <SimpleData name="STATE_FIPS">27</SimpleData>        <SimpleData name="CNTY_FIPS">077</SimpleData>        <SimpleData name="FIPS">27077</SimpleData>       </SchemaData>      </ExtendedData>      <Polygon>       <outerBoundaryIs>        <LinearRing>         <coordinates>          -95.21983978008106,48.54435777285278,0 -95.2117880336439,48.36900472565064,0 -94.43169006769016,48.36821243467153,0 -94.43063445677861,48.71078529488464,0 -94.57031275583248,48.71367627110935,0 -94.69443202246646,48.77761551038914,0 -94.68124996659202,48.87716132370134,0 -94.83203924782775,49.33080592976444,0 -95.1518673373111,49.37173013664073,0 -95.15774989320502,48.9999959019614,0 -95.2766571036275,48.99999118779378,0 -95.31012059635258,48.99339544568902,0 -95.32323587682019,48.97895631299367,0 -95.32091645456259,48.96097699585147,0 -95.3037572989727,48.94593890485217,0 -95.31417172404039,48.9320719995764,0 -95.29026017093044,48.90294958174787,0 -95.21957848050616,48.87944650348886,0 -95.13382124476209,48.89448474990023,0 -95.09491035007436,48.91176243313235,0 -95.09435905148671,48.71735751795557,0 -95.34105289190683,48.71517195733589,0 -95.34283127277658,48.546679319076,0 -95.21983978008106,48.54435777285278,0          </coordinates>        </LinearRing>       </outerBoundaryIs>      </Polygon>     </
