#!/usr/bin/perl
#
use strict;
use Getopt::Std;
use Geo::ShapeFile ;
use Geo::ShapeFile::Shape ;
use Geo::ShapeFile::Point ;
use XML::LibXML ;
use Math::Polygon ;
use Math::Polygon::Convex qw/chainHull_2D/ ;
use KMZ ;
use cvxPolygon;
use nlcd;
use Data::Dumper ;
$Data::Dumper::Indent = 1;
my $milesperlat = 69 ;
my $milesperlong = 54.6 ; 
our $opt_f = "" ;
our $opt_w = "" ;
our $opt_K = "proximity3" ;
our $opt_r = "" ;
our $opt_s = "" ;
our $opt_h = 0 ;
our $opt_k = "" ;
my $noclustering = 0;
getopts('s:f:r:K:w:hk:') ;

my @polycolors = (0xfffff8dc, 0xffffe4c4, 0xfff5deb3, 0xffd2b48c, 0xff90ed90,0xffadff2f, 0xff32cd32, 0xff228b22) ;
if ($opt_h) {
	HELP_MESSAGE() ;
	die ;
}

my (@whitelist,@wlist) ;
if ($opt_w ne "") {
	open (WL,$opt_w) || die "Can't open $opt_w for whitelist reading\n" ;
	while (<WL>) {
		chomp ;
		if (/^#.*$/) { next ; } 
		if (/^(\d+)/) {
			push @wlist,$1 ;
		}
	}
	my $nw = @wlist ;
	@whitelist = sort {$a <=> $b} @wlist ;
	print "$nw entries loaded\n" ;
}

if ($opt_K eq "no") {
	$noclustering  = 1 ;
}

my $shapefile = Geo::ShapeFile->new($opt_f, {no_cache => 1});
print STDERR "Loaded Shapefile!\n" ;

my @counties ;
my %countydata ;
my %terrainData ;
my @placemarks ;
my @newfolders ;
my @stylegroup;
my $fdrcnt = 0 ;
 

#  note that IDs are 1-based

my $totalArea = 0 ;
my $aoiCtr = 0;
printf STDERR "Loaded %d shapes\n",$shapefile->shapes() ;
foreach my $id (1 .. $shapefile->shapes()) {
	my $shape = $shapefile->get_shp_record($id);
# see Geo::ShapeFile::Shape docs for what to do with $shape
	my %db = $shapefile->get_dbf_record($id);
	next unless ($opt_s eq "" || ($db{'state_abbr'} eq $opt_s))  ;
	my $record = $shapefile->get_shp_record($id) ;
	my ($np,$npt,$st) ;
	$np = $record->num_parts ;
	$npt = $record->num_points ;
	$st = $record->shape_type ;
	printf "Record has %d parts, %d points is of type %s ", $np, $npt, $st ;

	my @pcoords ;
	my $nxt = 0;
  	for(1 .. $record->num_parts) {
  		my $part = $record->get_part($_);
		my @points = $record->points() ;
		foreach my $pt (@points) {
			my @xy ;
			$xy[0] = $pt->get_x();
			$xy[1] = $pt->get_y() ;
			@pcoords[$nxt++] = \@xy ;
		}
	}
	print "(Loaded $nxt points) " ;


  # ... do something here, draw a map maybe
	print "county $db{'county'} cbg = $db{'cbg_id'}\n" ;
	if ($opt_w && !whiteListed(\@whitelist,$db{'cbg_id'})) {
		next ;
	}

	my $county = $db{'county'} ;
	print "County $county\n" ;
	if (!defined %countydata{$county}) {
		push @counties, $county;
		my @listAois ;
		my @cx ;
		my @cy ;
		my @clusters ;
		my %data ;
		my $aoiCtr = 0;
		$data{'aois'} = \@listAois ;
		$data{'cx'}= \@cx ;
		$data{'cy'} = \@cy ;
		$data{'centroid'} = \$aoiCtr ;
		$data{'clusters'} = \@clusters ; 
		$countydata{$county} = \%data ;
		print "Created new county $county\n" ;
	}
	my @polygonlist ;
	my $nxtp=0;

	my $listofAois = $countydata{$county}{'aois'} ;
	my $cx = $countydata{$county}{'cx'} ;
	my $cy = $countydata{$county}{'cy'} ;
	my $countyAoiCtr = $countydata{$county}{'centroid'};
	my $holearea = 0;
	#
	# Close the pcoords
	# 
	{
		my @first = @{$pcoords[0]} ;
		my @last = @{$pcoords[$#pcoords]} ;
		if ($first[0] != $last[0] || $first[1] != $last[1]) {
			splice @pcoords,@pcoords - 1, 1, \@first;
		}
	}
	my $nxtaoi = chainHull_2D @pcoords ;
	$nxtaoi->simplify() ;
	my $pcnt = $nxtaoi->nrPoints ;
	my $parea = $nxtaoi->area()*$milesperlat*$milesperlong ;
	$parea -= $holearea ;
	printf "Converted placemark to convex hull of %d points, area = %.4g (closed=%d) ", $pcnt,$parea,$nxtaoi->isClosed() ;
	#next unless ($parea > $EPS) ;
	next unless ($nxtaoi->isClosed()) ;
	my $center =  $nxtaoi->centroid() ;
	($$cx[$$countyAoiCtr],$$cy[$$countyAoiCtr]) = @$center ;
	my %tdata ; 
	{
			my %histogram ;
			my $npts = int($nxtaoi->area()*$milesperlat*$milesperlong)+1 ;
			print "Calling samplehistogram with $npts points for placemark $db{'cbg_id'}:" ;
			nlcd::sampleHistogram($nxtaoi,$npts*100,\%histogram) ;
			#my $totalrange = @polycolors ;
			my $tcode = getTerrainCodeFromHistogram(\%histogram,100); 
			$tdata{'terrainType'} = $tcode  ;
			
			print "$tdata{'terrainType'}\n" ;
	}
	$tdata{'area'} = $parea  ;
	$terrainData{$db{'cbg_id'}} = \%tdata ;
		
	my $desc = sprintf"%10s\n",$db{'ORIG_FID'};
	my @holes ;
	my ($pname,$pid) ;
	$pname = $db{'cbg_id'} ;
	$pid = sprintf("ID_%d",$db{'ORIG_FID'}) ;
	my $pm = makeNewPlacemark($pname,$nxtaoi,\@holes,"",$pid,$desc) ;
	push @placemarks,$pm;
		
	#print " centroid=$$cx[$$countyAoiCtr],$$cy[$$countyAoiCtr]\n" ; 
	my %aoihash = ( 'name' => $db{'cbg_id'} , 'polygon' => \$nxtaoi, 'fid' => $db{'ORIG_FID'}) ;
	push @$listofAois,\%aoihash ;
	$totalArea += $parea ;
	$aoiCtr++ ;
}
printf " Pushed %d placemarks\n", @placemarks ;
srand($$) ;

# 
# Process the file and load placemarks. Each Placemark is a CBG
# The county information is in the description
#
use Math::Polygon::Convex qw/chainHull_2D/ ;

# 
# Now convert placemarks into polygons
#
print "$aoiCtr AOIs recorded, total area of $totalArea: " ;
for my $cname (keys %countydata) {
	my $pc = $countydata{$cname}{'aois'};
	my $np = @$pc ;
	print "$cname -> $np ",
}
print "\n" ;

#
# Clustering
#

my (@clusters,@clustercenters,$numclusters,@tclusters,$nc) ;
$nc = $numclusters = 0;
foreach my $cn (keys %countydata)
{
	my @aois = @{$countydata{$cn}{'aois'}} ;
	if ($opt_K eq "Kmeans"){
	       if (@aois > 9) {
		print "Trying K-means clustering for $cn \n" ;
		($clusters[$nc],$clustercenters[$nc],$tclusters[$nc]) = 
			aoiClustersKmeans($countydata{$cn}{'aois'},$countydata{$cn}{'cx'},$countydata{$cn}{'cy'},$totalArea) ;
		}
		else {
			my $sthresh = 4 ;
			print "Trying Proximity clustering for $cn ($sthresh) \n" ;
			($clusters[$nc],$tclusters[$nc]) = 
				aoiClustersProximity($countydata{$cn}{'aois'},$sthresh) ;
		}
	}
	elsif ($opt_K =~ /proximity([.0-9]+)/) {
		my $thresh = 5 ;
		($opt_K =~ /proximity([.0-9]+)/) && do {
			$thresh = $1 ; 
		} ;
		print "Trying Proximity clustering for $cn ($thresh) \n" ;
		($clusters[$nc],$tclusters[$nc]) = 
			aoiClustersProximity($countydata{$cn}{'aois'},$thresh) ;
	}
	elsif ($noclustering == 1) {
		($clusters[$nc],$tclusters[$nc]) =
			aoiNoClustering($countydata{$cn}{'aois'}) ;
	}
	elsif (-e $opt_K) {
		($clusters[$nc],$tclusters[$nc]) = 
			aoiLoadClusterFile($cn,$opt_K) ;
	}
	else {
		die "Unknown clustering method $opt_K\n" ;
	}
	$countydata{$cn}{'clusterMap'} = $clusters[$nc] ;
	$numclusters += $tclusters[$nc] ;
	print "$tclusters[$nc] clusters returned (total=$numclusters)\n" ;
	$nc++ ;
}

# Prepare the styles
for ($nc = 0; $nc<@polycolors; $nc++){
	print "Adding new style $nc\n" ;
	my %newstyle ;
	my %newst = makeNewSolidStyle($nc,$polycolors[$nc],192,1) ;
	$newstyle{'Style'} = \%newst ;
	push @stylegroup, \%newstyle ;
}

my $i = 0;
my $newcn = 0;
foreach my $cn (keys %countydata)
{
	my @newclusters ;
	my $ccn = 0 ;
	foreach my $newc (keys %{$clusters[$i]}) {
		my @clusterpoints ;
		my @clist = @{$clusters[$i]->{$newc}} ;
		my @plist ;
		my @hlist ; 
		my $cliststring = "" ;
		print "newc = $newc newcn = $newcn\n" ;
		next if (@clist == 0) ;
		for my $pk (@clist){
			my $pgon = 0 ;
			my $preflist = $countydata{$cn}{'aois'};
			$cliststring .= sprintf("%s:",$pk) ;
			foreach my $pref (@$preflist) {
				if ($$pref{'name'} eq $pk) {
					$pgon = $$pref{'polygon'} ;
					last ;
				}
			}
			if ($pgon == 0) {
				print "Couldn't find $pk in data for $counties[$i]\n" ;
				next ;
			}
		#		if ($pgon == 0) {die "Can't find $pk in list of placemarks\n" ;}
			$$pgon->simplify() ;
			my @points = $$pgon->points() ;
			splice @clusterpoints,@clusterpoints,0,@points ;
			push @plist,$$pgon ;
		}
		next if ((@clusterpoints == 0) || (@plist == 0 )) ;
		my $badclusterpoly = chainHull_2D @clusterpoints ;
		my $clusterpoly = Math::Polygon->new(cvxPolygon::combinePolygonsConvex(\@plist)) ;
		printf "Convex operation returns polygon with %d points, closed=%d\n",$clusterpoly->nrPoints(),$clusterpoly->isClosed() ;
		my %options ;
		$options{''} = 1 ;
		@clusterpoints = $clusterpoly->points() ;
		my %cinf ;
		$cinf{'name'} = $newc;
		$cinf{'poly'} = $badclusterpoly ;
		push @{$countydata{$cn}{'clusters'}} , \%cinf ;

		my $description = makeNewDescription("Cluster $newcn, county $cn List of CBGs:$cliststring\n") ;
		my $cstyle ;
		{
			my $cname ;
			$cstyle = sprintf("TerrainStyle%.3d",$newcn%@polycolors) ;
			# Find the pref and copy it into the cluster data ;
			my @pmarkname = @{$clusters[$i]->{$newc}} ;
			my @consolidatedPolygonList ;
			if ($noclustering) {
				$cname = sprintf("CBG_%s" , $cliststring) ;
			}
			else {
				$cname = sprintf("%s/%s", $cn, $newc) ;
			}
			foreach my $pmark (@pmarkname) {
				print "Moving $pmark to newcluster:" ;
				my $found = -1 ;
				FOUND: for (my $fcount=0; $fcount < @placemarks; $fcount++)
				{
					my $plmark = $placemarks[$fcount] ;
					if ($$plmark{'Placemark'}{'name'} eq $pmark) {
						$found = $fcount ;
						print "found at $found, " ;
						#$$plmark{'Placemark'}{'styleUrl'} = $cstyle ;
						my $pgons = $$plmark{'Placemark'}{'MultiGeometry'}{'AbstractGeometryGroup'} ;
						splice @consolidatedPolygonList,@consolidatedPolygonList,0, @$pgons ;
						splice @placemarks, $found,1 ;
						my $nleft =@placemarks ;
						print "$nleft left\n" ;
						last FOUND;
					}
				}
				if ($found == -1){
					die "Couldn't find $pmark!\n" ;
				}
			}
			my $newcluster = makeNewClusterFromPlacemark($cn,\@consolidatedPolygonList,$ccn,$cstyle,$description,$cname) ;
			push @newclusters,$newcluster ;
		}
		$newcn++ ; $ccn++ ; 
		#printf("newcn -> $newcn\n") ;
	}
	my $nclusters = @newclusters ;
	print "Adding $nclusters placemarks for $cn\n" ; 
	my %newfolder ; 
	my %foldercontainer ;
	makeNewFolder($cn,\@newclusters, \%newfolder, $fdrcnt++) ;
	$foldercontainer{'Folder'} = \%newfolder ;
	push @newfolders, \%foldercontainer ;
	$i++ ;
}

if ($opt_k ne "") {
	my $dhash ;
	my ($nstyles,$nfolders) ;
	$nstyles = @stylegroup ;
	$nfolders = @newfolders;
	print "$nstyles styles $nfolders folders\n" ;
	if ($opt_s eq "") {
		$dhash = makeNewDocument("Document",\@newfolders,\@stylegroup) ;
	}
	else {
		$dhash = makeNewDocument($opt_s,\@newfolders,\@stylegroup) ;
	}
	makeNewFile($dhash,$opt_k) ;
}


if ($opt_r ne "") {
	printReport(\%countydata,$opt_r,\%terrainData,$noclustering) ;
}
#
# Last step. Dump the state bounding boxes on the screen

exit(1) ;


use Algorithm::KMeans ;
sub aoiClustersKmeans{
	my $aoisref = shift ;
	my $cxref = shift ;
	my $cyref = shift ;
	my $tA = shift ;
	my $nc = 0;
	my $datafile = "aoi" . $$ . ".csv" ;
	my $kmin = int($tA/2000) ;
	my $kmax = int(sqrt(@$aoisref/2)) ;
	print "Initial estimate kmax=$kmax kmin=$kmin\n" ; 
	#	if (@$aoisref < 9) {
	#	my @list ;
	#	my @center = ($$cxref[0],$$cyref[0]) ;
	#	for (my $i = 0 ; $i <@$aoisref; $i++) {
	#		push @list, ${$$aoisref[$i]}{'name'} ;
	#	}
	#	my %sc ;
	#	$sc{'cluster0'} = \@list;
	#	return (\%sc, \@center,1) ;
	#}


	while ($kmax <= $kmin && $kmin > 4) {
		$kmin -= $kmin << 2;
	}
	if ($kmax <= $kmin) {
		$kmax = 12 ; $kmin = 6 ;
	}

		$kmax = $kmin = int(sqrt(@$aoisref/2)) ;
	open (FTMP, ">",$datafile) || die "Can't open $datafile for creating cluster list\n" ;
	for (my $aoi=0 ; $aoi < @$aoisref; $aoi++) {
		printf FTMP "%s,%.6g,%.6g\n", ${$$aoisref[$aoi]}{'name'}, $$cxref[$aoi], $$cyref[$aoi] ;
	}
	close (FTMP) ;
	print "Trying K-means with $kmax,$kmin clusters\n" ;
	my $clusterer = Algorithm::KMeans->new(
		datafile        => $datafile,
                mask            => "N11",
                K               => 0,
		Kmin		=> $kmin,
		Kmax		=> $kmax,
                cluster_seeding => 'random',   
                use_mahalanobis_metric => 0,  
                terminal_output => 0,
                write_clusters_to_files => 0 ) ;
	$clusterer->read_data_from_file() ;
	my ($clusters,$clusterCenters) = $clusterer->kmeans() ;
	foreach my $cluster_id (sort keys %{$clusters}) {
		$nc++ ;
		print "\n$cluster_id   =>   @{$clusters->{$cluster_id}}\n";
	}
	unlink($datafile) ;
	printf "Generated %d clusters\n",$nc;
	return ($clusters,$clusterCenters,$nc) ;
	
}

use proximityCluster ;
sub aoiClustersProximity{
	my $aoisref = shift ;
	my $thresh = shift ;
	my @boxes ;
	for (my $aoi=0 ; $aoi < @$aoisref; $aoi++) {
		my %box ;
		$box{'id'} = ${$$aoisref[$aoi]}{'name'} ;
		my $poly =  $$aoisref[$aoi]{'polygon'} ;
		my $cnt = $$poly->centroid ;
		$box{'centroid'} = $cnt ;
		$box{'area'} = $$poly->area * $milesperlat * $milesperlong ;
		#printf "Polygon of centroid %.4g,%.4g, area %.4g\n", $$cnt[0], $$cnt[1], $$poly->area ;
		push @boxes,\%box ;
	}
	my $nb = @boxes ;
	print "Produced array of size $nb boxes\n" ;
	my %clusters = proximityCluster::proximityCluster(\@boxes,$thresh) ;
	my $nc = 0 ;
	foreach my $cluster_id (sort keys %clusters) {
		print "\n$cluster_id   =>   @{$clusters{$cluster_id}}\n";
		$nc++ ;
	}
	return \%clusters,$nc ;
}

sub aoiNoClustering{
	my $aoisref = shift ;
	my %clusters ;
	my $aoi ;
	for ($aoi=0; $aoi < @$aoisref ;$aoi++) {
		my @cbglist ;
		my $key = "CBG" . $$aoisref[$aoi]{'name'} ;
		push @cbglist, $$aoisref[$aoi]{'name'} ; 
		$clusters{$key} = \@cbglist ;
	}
	return \%clusters,$aoi ;
}

sub aoiLoadClusterFile {
	my $cn = shift ;
	my $fname = shift ;
	my %clusters ;
	my $nc = 0;
	open (CR,$fname) || die "Can't open $fname for reading:$!\n" ;
	while (<CR>) {
		chomp ;
		if (/^#.*$/) { next ; }
		my @fields = split(/,/) ;
		next unless ($fields[0] eq $cn) ; 
		my $clusterid = $fields[1] ;
		my @cbgs = split(/:/,$fields[$#fields]) ;
		print "County $cn, cluster $clusterid:" ;
		foreach my $cbgid (@cbgs) {
			print "$cbgid " ;
		}
		print "\n" ;
		$clusters{$clusterid} = \@cbgs ;
		$nc++ ;
	}
	close (CR) ;
	return \%clusters,$nc ;
}

sub prompt{
	my $continue = shift ;
	if ($$continue == 1) { return 1 ; }
	else {
		print ("Continue? [Y/n/c]\n") ;
		$_ = <> ;
		chomp ;
		if ($_ eq 'c') { $$continue = 1 ; return 1 ; }
		elsif ($_ eq 'n') { return 0 ; }
		else { return 1 ; }
	}
}

sub findInClusters {
	my $name = shift ;
	my $clusters = shift ;
	foreach my $cid (keys %{$clusters})
	{
		for my $centry (@{$clusters->{$cid}}) {
			if ($centry eq $name) {
				#				print "Matched $name to $cid\n" ;
				my $tok ;
				($cid =~ /cluster(\d+)/) && do { $tok = $1 ; } ;
				return $tok ;
			}
		}
	}
	return -1;
}


sub arrayToPolygon{
	my $cref = shift ;
	my @coords = @$cref ;
	my @plist ;
	my $cntr = @coords ;
	my $nxt = 0 ;
	
	#	printf "Array to Polygon: array of size %d\n",($#coords+1) ;
	for (my $i = 0; $i <= $#coords; $i++) {
		my @xy ;
		my ($x,$y,$z) = split(/,/,$coords[$i]) ;
		$xy[0] = $x ;
		$xy[1] = $y ;
		@plist[$nxt++] = \@xy ;
	}
	@plist ;
}



sub getCounty{
	my $dstr = shift ;
	my $clist = shift ;
	my $cname = "" ;
	my $fnd = 0 ;
	if ($dstr =~ m@<td>county</td>\s*<td>([^<]+)</td>@s) {
		$cname = $1 ;
		for my $ce (@$clist) {
			if ($ce eq $cname) {
				$fnd = 1 ;
				last ;
			}
		}
		return ($cname,$fnd) ;
	}
	return ($cname,$fnd) ;
}
	

# Formula for tower to cell density
# c = 68.24 - 0.166*tc ;
# chigher = 66.12 - 0.279*tc ;
sub printReport{
	my $cdata = shift ;
	my $ofile = shift ;
	my $tdata = shift ;
	my $noclustering = shift ;
	#	print Dumper $tdata ;
	#return 0;
	open (FREP,">", "$ofile") || die "Can't open $ofile for writing\n" ; 
	print FREP "County,Cluster id,Area (sq.miles), CBG ARea, Holes, %Coverage, Weighted Terrain Code(0-99),Number of Towers, Number of Towers (64QAM and better),Number of Towers (Cluster weighted), Number of Towers (64QAM and better,clusterweighted)," ;
	if ($noclustering) {
		print FREP "CBGID,FID\n" ; 
	}
	else {
		print FREP "CBG List\n" ;
	}


	print "Processing counties..." ;
	my ($totalArea,$totalTowers,$totalTowers2,$totalCbgArea) ;
	$totalArea = $totalTowers = $totalTowers2 = $totalCbgArea = 0 ;
	for my $cname (sort keys %$cdata) {
		my $clist = $$cdata{$cname}{'clusters'} ;
		my $clusterlist = $$cdata{$cname}{'clusterMap'} ;
		my $listofAois = $$cdata{$cname}{'aois'} ;
		my %aoiArea ;
		my %aoiHoleArea ;
		my %towers;
		my %towers2;
		my %terrainCode ;
		my %fid ;
		for my $aoi (@$listofAois) {
			#print "Name $$aoi{'name'}..." ;
			my $poly = $$aoi{'polygon'} ;
			my $holes = $$aoi{'holes'} ;
			$fid{$$aoi{'name'}} = $$aoi{'fid'} ;
			$aoiArea{$$aoi{'name'}} = $$poly->area * $milesperlat * $milesperlong ; 
			foreach my $hole (@$holes) {
				$aoiHoleArea{$$aoi{'name'}} += $hole->area * $milesperlat * $milesperlong ;
			}
			#printf "area = %.4g..", $$poly->area ;
			$terrainCode{$$aoi{'name'}} = $$tdata{$$aoi{'name'}}{'terrainType'} ;
			{
				my $tc = $terrainCode{$$aoi{'name'}} ;
				my $cellDensity = 68.24  - 0.166*$tc ;
				my $cellDensity2 = 66.12 - 0.279*$tc ;
				print "$$aoi{'name'}: Terrain code $tc, celldensity=$cellDensity, celldensity2 = $cellDensity2 " ;
				if ($cellDensity2 > $cellDensity) { $cellDensity2 = $cellDensity ; }
				if ($cellDensity == 0 || $cellDensity2 == 0) { die "terrain=$terrainCode{$$aoi{'name'}} cname = $cname aoi = $$aoi{'name'} density=$cellDensity\n" ; }
				printf "area=%.4g ",($aoiArea{$$aoi{'name'}} - $aoiHoleArea{$$aoi{'name'}}) ;
				my $aoiTower = ((($aoiArea{$$aoi{'name'}} - $aoiHoleArea{$$aoi{'name'}})/$cellDensity)) ;
				$towers{$$aoi{'name'}} += $aoiTower ;

				my $aoiTower2 =((($aoiArea{$$aoi{'name'}} - $aoiHoleArea{$$aoi{'name'}})/$cellDensity2)) ;
				$towers2{$$aoi{'name'}} += $aoiTower2 ;
				print "aoiTower=$aoiTower aoiTower2=$aoiTower2\n" ;
			}
		}

		for my $cid (@$clist) {
			my $clusterarea = $milesperlat*$milesperlong*$$cid{'poly'}->area() ;
			my $ostring = "" ;
			my $fstring = "" ;
			my $cbgClusterArea = 0 ; 
			my $cbgClusterHoleArea = 0 ; 
			my $twrs = 0;
			my $twrs2 = 0;
			my $weightedTerrainCode= 0 ;
			my $cbglist = $$clusterlist{$$cid{'name'}} ;
			for my $cbg (@$cbglist) {

				if ($ostring eq "") { $ostring = $cbg ; }
				else { $ostring .= ":".$cbg ; }
				if ($fstring eq "") { $fstring = $fid{$cbg} ; }
				else { $fstring .= ":".$fid{$cbg} ; }

				$cbgClusterArea += $aoiArea{$cbg} ; 
				$cbgClusterHoleArea += $aoiHoleArea{$cbg} ;
				$twrs += $towers{$cbg};
				$twrs2 += $towers2{$cbg};
				$weightedTerrainCode += $terrainCode{$cbg}*($aoiArea{$cbg} - $aoiHoleArea{$cbg})  ;
				print "$cbg -> $terrainCode{$cbg}, area=$aoiArea{$cbg} hole=$aoiHoleArea{$cbg} " ;
			}
			$twrs = int(0.5+$twrs) ; if ($twrs < 1) { $twrs = 1 ; }
			$twrs2 = int(0.5+$twrs2) ; if ($twrs2 < 1) { $twrs2 = 1 ; }
			print "weighted = $weightedTerrainCode " ;
			$weightedTerrainCode = int($weightedTerrainCode/$cbgClusterArea) ;
			print "normalized = $weightedTerrainCode\n" ;
			my ($ctwrs,$ctwrs2) ;
			{
				my $clusterCellDensity = 68.24  - 0.166*$weightedTerrainCode ;
				my $clusterCellDensity2 = 66.12 - 0.279*$weightedTerrainCode ;
				if ($clusterCellDensity2 < $clusterCellDensity) {
					$clusterCellDensity = $clusterCellDensity ;
				}
				$ctwrs = int(0.5 + ($clusterarea/$clusterCellDensity)) ;
				$ctwrs2 = int(0.5 + ($clusterarea/$clusterCellDensity2)) ;
				if ($ctwrs < 1) { $ctwrs = 1 } ;
				if ($ctwrs2 < 1) { $ctwrs2 = 1 } ;
				printf "Cluster level:cluster area:%.6g, clusterdensities=%.4g %.4g ",
					$clusterarea, $clusterCellDensity, $clusterCellDensity2,
				print "towers: $ctwrs $ctwrs2, $twrs,$twrs2\n" ;
			}
			my $pc = int(100.0*($cbgClusterArea - $cbgClusterHoleArea)/$clusterarea) ; 
			printf FREP "%.10s,%10s,%.6g,%.4g,%.4g,%d%%,%d,%d,%d,%d,%d,",
				$cname,$$cid{'name'},
				$clusterarea,$cbgClusterArea,$cbgClusterHoleArea,
				$pc,$weightedTerrainCode,$twrs,$twrs2,$ctwrs,$ctwrs2;
			if ($noclustering) { print FREP "$ostring,$fstring\n" ; }
			else {print FREP "$ostring\n" ; }

			if ($ctwrs < $twrs) { $twrs = $ctwrs ; }
			if ($ctwrs2 < $twrs2) { $twrs2 = $ctwrs2 ; }
			$totalArea += $clusterarea ;
			$totalCbgArea += $cbgClusterArea ;
			$totalTowers += $twrs ;
			$totalTowers2 += $twrs2 ;
		}
	}
	print "\n";
	print FREP "Consolidated: Towers(all coverage) = $totalTowers, Towers(64QAM and better)=$totalTowers2,Area = $totalArea,CBG Area = $totalCbgArea\n" ;
	printf "Consolidated: Towers(all coverage)=%d, Towers(64QAM and better)=%d, Area=%.6g, CBG Area=%.6g\n",
       	$totalTowers,$totalTowers2,$totalArea,$totalCbgArea ;
	close(FREP) ;
}

sub whiteListed {
	my $wlist = shift ;
	my $entry = shift ;
	for (my $i = 0; $i<@$wlist; $i++) {
		if ($entry == $$wlist[$i]) { return 1 ; }
		elsif ($entry < $$wlist[$i]) { return 0 ; }
	}
	return 0;
}

sub HELP_MESSAGE {
print STDERR <<EOH
Usage: $0 -f <input shp file> -r <report file>  -K <Kmeans/proximity/no>  -s <two letter state abbr> -w <whitelist file> -k <op kmz file>
EOH
;
}
