#!/usr/bin/perl
#


use strict ;
use Getopt::Std ;
use Geo::KML ;
use Data::Dumper ;
use XML::LibXML ;
use Math::Polygon ;
use KMZ ;
use cvxPolygon;
use nlcd;

$Data::Dumper::Indent = 1;
my $milesperlat = 69 ;
my $milesperlong = 54.6 ; 
my $prompt = 1;


our $opt_f = "" ;
our $opt_k = "" ;
our $opt_r = "sampleReport.csv" ;
our $opt_K = "proximity3" ;
our $opt_h ;
our $opt_p = 0 ;
our $opt_t = "" ;
our $opt_w = "" ;
our $opt_C = "" ;
getopts('f:k:r:K:hw:C:') ;
if ($opt_h) {
	HELP_MESSAGE() ;
	exit(1) ;
}
my @colors = (0xffff0000, 0xff00ff00, 0xff0000ff, 0xffaa3333, 0xff33aa22,0xff00cccc, 0xff22cc22, 0xff22aacc) ;
my @polycolors = (0xfffff8dc, 0xffffe4c4, 0xfff5deb3, 0xffd2b48c, 0xff90ed90,0xffadff2f, 0xff32cd32, 0xff228b22) ;
my %pmlistentry ;
my $noclustering = 0;

#
# We need a file to load
#
my $statename = "" ;
if ($opt_f eq "") {
	HELP_MESSAGE() ;
	die ;
}
else {
	if ($opt_f =~ m@.*/([A-Z]{2}).kmz@) {
		$statename = $1 ;
	}
	else {
		print "No Statename\n" ;
	}

	open(F1,$opt_f) || die "Can't open file $opt_f\n" ; 
	if ($opt_k eq "") {
		($opt_f =~ m@.*([A-Z]{2}).kmz@) && 
			do {
				$opt_k = $1 . "mod.kmz" ; 
				print "output kmz file=$opt_k\n"; 
			} ;
	}
}
my (@whitelist,@wlist) ;
if ($opt_w) {
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

if ($opt_p) { $prompt = 0 ; }

srand($$) ;

# 
# Process the file and load placemarks. Each Placemark is a CBG
# The county information is in the description
#
print "Opening $opt_f for processing...\n" ;
my ($ns,$data) = Geo::KML->readKML($opt_f) ;
my $dhash = %$data{'Document'} ;
print Dumper $data ;
exit(1) ;

#for (keys %$dhash) {
#	print "Key $_: Value $$dhash{$_}\n" ;
$$dhash{'name'} = $statename ;
my $featuregroup = $$dhash{'AbstractFeatureGroup'} ;
my $stylegroup = $$dhash{'AbstractStyleSelectorGroup'} ;

my $EPS = 0.001 ;
my $totalArea = 0 ;
my $aoiCtr=0;
my $cxavg = 0 ;
my $cyavg = 0 ;
my @placemarkhashes;
my $placemarks = 0;
my @featureref ;
my $featurecnt = 0 ;
foreach my $fg (@$featuregroup) {
	for my $fkey (keys %$fg) {
		print "Key $fkey: Value $$fg{$fkey}\n" ;
		next unless ($fkey eq 'Folder') ;
		my $fder = %$fg{$fkey} ;
		for my $fderkey (keys %$fder) {
			print "Folder Key $fderkey: Value $$fder{$fderkey}\n" ;
			if ($fderkey eq "name") {
				$$fder{$fderkey} = "Not in whitelist" ;
			}
			if ($fderkey eq "description") {
				$$fder{$fderkey} = $statename. ":CBGs which are not featured in the whitelist" ;
			}
			next unless ($fderkey eq 'AbstractFeatureGroup') ;
			$featureref[$featurecnt]  = $$fder{'AbstractFeatureGroup'} ;
			foreach my $fcount (@{$featureref[$featurecnt]})
			{
				for my $fcntkey (keys %$fcount) {
					#					print "Feature Key $fcntkey: Value $$fcount{$fcntkey}\n" ;
					if ($fcntkey eq 'Placemark') { 
						my $pref = $$fcount{$fcntkey} ;
						my $geometries = $$pref{'MultiGeometry'}{'AbstractGeometryGroup'} ;
						foreach my $geomkey (@$geometries) {
							my $coordinates = $$geomkey{'Polygon'}{'outerBoundaryIs'}{'LinearRing'}{'coordinates'} ;
							splice @$coordinates,1,@$coordinates - 1 ;
							if (defined ($$geomkey{'Polygon'}{'innerBoundaryIs'})) {
								my $holes = $$geomkey{'Polygon'}{'innerBoundaryIs'};
								my $nh = @$holes ;
								foreach my $hl (@$holes) {
									my $thole = $$hl{'LinearRing'}{'coordinates'} ;
									splice @$thole,1,@$thole - 1 ;
								}
								print "Found $nh holes!\n" ;
							}
						}
						%pmlistentry = %$fcount ; 
						push @placemarkhashes,$$fcount{$fcntkey} ; $placemarks++; 
					}
				}
			}
			$featurecnt++ ;
		}
		
	}
}
print "$placemarks Placemarks found, $featurecnt Features found\n" ;
print Dumper $data ;
exit(1) ;


use Math::Polygon::Convex qw/chainHull_2D/ ;

my @counties ;
my %countydata ;
my %terrainData ;
# 
# Now convert placemarks into polygons
#
foreach my $pref (@placemarkhashes) {
	my $countyAoiCtr = 0;
	my $geometries = $$pref{'MultiGeometry'}{'AbstractGeometryGroup'} ;
	my $description = $$pref{'description'} ;
	if ($opt_w && !whiteListed(\@whitelist,$$pref{'name'})) {
		foreach my $geomkey (@$geometries) {
			undef $$geomkey{'Polygon'}{'altitudeMode'} ;
		}
		next ;
	}

	my ($county,$new) = getCounty($description,\@counties) ;
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
	}
	my @pcoords ;
	my @polygonlist ;
	my $nxtp=0;

	my $listofAois = $countydata{$county}{'aois'} ;
	my $cx = $countydata{$county}{'cx'} ;
	my $cy = $countydata{$county}{'cy'} ;
	my $countyAoiCtr = $countydata{$county}{'centroid'};
	my @polyholes ;
	my $holearea = 0;
	foreach my $geomkey (@$geometries) {
		my $coordinates = $$geomkey{'Polygon'}{'outerBoundaryIs'}{'LinearRing'}{'coordinates'} ;
		my @plist = arrayToPolygon($coordinates) ;
		splice @pcoords,@pcoords,0,@plist ;
		$polygonlist[$nxtp++] = Math::Polygon->new(@plist) ;
		if (defined($$geomkey{'Polygon'}{'innerBoundaryIs'})) {
			my $holes = $$geomkey{'Polygon'}{'innerBoundaryIs'} ;
			my $nh  = @$holes ;
			if ($nh) { 
				print "Found $nh holes in $$pref{'name'}: " ;
				foreach my $hole (@$holes) {
					my $hp = Math::Polygon->new(arrayToPolygon($$hole{'LinearRing'}{'coordinates'})) ;
					printf "hole of area %.4g, ", $hp->area * $milesperlat * $milesperlong ;
					push @polyholes,$hp ;
					$holearea += $hp->area() * $milesperlat * $milesperlong ;
				}
				print "\n" ;
			}
		}
		undef $$geomkey{'Polygon'}{'altitudeMode'} ;
	#{ print "coordinate string: $$geomkey{'Polygon'}{'outerBoundaryIs'}{'LinearRing'}{'coordinates'}\n" ; }
	}
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
	#	my $nxtaoi = Math::Polygon->new(cvxPolygon::combinePolygonsConvex(\@polygonlist)) ;
	$nxtaoi->simplify() ;
	my $pcnt = $nxtaoi->nrPoints ;
	my $parea = $nxtaoi->area()*$milesperlat*$milesperlong ;
	$parea -= $holearea ;
	printf "Converted placemark to convex hull of %d points, area = %.4g (closed=%d) ", $pcnt,$parea,$nxtaoi->isClosed() ;
	my $numholes = @polyholes ;
	print "Found $numholes holes\n" ; 
	next unless ($parea > $EPS) ;
	next unless ($nxtaoi->isClosed()) ;
	my $center =  $nxtaoi->centroid() ;
	($$cx[$$countyAoiCtr],$$cy[$$countyAoiCtr]) = @$center ;
	my %tdata ; 
	{
			my %histogram ;
			my $npts = int($nxtaoi->area()*$milesperlat*$milesperlong)+1 ;
			print "Calling samplehistogram with $npts points for placemark $$pref{'name'}:" ;
			nlcd::sampleHistogram($nxtaoi,$npts*100,\%histogram) ;
			#my $totalrange = @polycolors ;
			my $tcode = getTerrainCodeFromHistogram(\%histogram,100); 
			$tdata{'terrainType'} = $tcode  ;
			
			print "$tdata{'terrainType'}\n" ;
	}
	$tdata{'area'} = $parea  ;
	$terrainData{$$pref{'name'}} = \%tdata ;
		
		
	#print " centroid=$$cx[$$countyAoiCtr],$$cy[$$countyAoiCtr]\n" ; 
	my %aoihash = ( 'name' => $$pref{'name'} , 'polygon' => \$nxtaoi, 'holes' => \@polyholes ) ;
	push @$listofAois,\%aoihash ;
	$totalArea += $parea ;
	$$countyAoiCtr++ ;
	$aoiCtr++ ;
}
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
			die unless (prompt(\$prompt) == 1) ;
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
my $nc = 0;
my $clr ;
foreach my $stylehash (@$stylegroup) {
	for (keys %$stylehash) {
		print "Key $_: Value $$stylehash{$_}\n" ;
		my $st = $$stylehash{'Style'} ;
		my $ps = $$st{'PolyStyle'} ;
		$clr = $$ps{'color'} ;
		printf "Current colour = %x\n" , $clr ;
	}
	$nc++;
}
print "Found $nc styles\n" ;
my $oldnc = $nc ;
$nc = 0;
# 
# Create new styles, to be allocated randomly to clusters
#
for ($nc = 0; $nc<@colors; $nc++){
	print "Adding new style $nc\n" ;
	my %newstyle ;
	my %newst = makeNewOutlineStyle($nc,$colors[$nc]) ;
	$newstyle{'Style'} = \%newst ;
	push @$stylegroup, \%newstyle ;
}
# 
# Create new terrain styles, to be allocated randomly to clusters
#
for ($nc = 0; $nc<@polycolors; $nc++){
	print "Adding new style $nc\n" ;
	my %newstyle ;
	my %newst = makeNewSolidStyle($nc,$polycolors[$nc],192,1) ;
	$newstyle{'Style'} = \%newst ;
	push @$stylegroup, \%newstyle ;
}
#
# Make a new grey style
my (%greystyle,%greyst,$greyid) ;
$greyid = @polycolors ;
%greyst = makeNewSolidStyle($greyid,0xff7080240,240,0) ;
$greystyle{'Style'} = \%greyst ;
push @$stylegroup,\%greystyle ;

my $newcn = $oldnc ;

#
# Now each cluster is enclosed in a single, convex polygon
# All placemarks within the cluster are coloured the same.
# We keep track using styleIdHash ;
#
my $i = 0;
my @newfolders ;
my %styleIdHash ;
my $styleCounter = 0 ;
my $fdrcnt = (1 - $noclustering) ;
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
					my $listofHoles = $$pref{'holes'} ;
					if (@$listofHoles) {
						splice @hlist,@hlist,0,@$listofHoles;
					}
					$styleIdHash{$$pref{'name'}} = $styleCounter;
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
		my $newcluster ;
		#		if ($noclustering == 0) {
		#	$cstyle = sprintf("ClusterStyle%.3d",$newcn%@colors) ;
		#	$newcluster = makeNewCluster($cn,$clusterpoly,$ccn,\@hlist,$cstyle,$description) ;
		#}
		#else 
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
			#$newcluster = makeNewCluster($cn,$clusterpoly,$ccn,\@hlist,$cstyle,$description, $cname) ;
				FOUND: for (my $fcount=0; $fcount < @{$featureref[0]}; $fcount++)
				{
					my $feature = ${$featureref[0]}[$fcount] ;
					foreach my $fkey (%$feature) {
						next unless ($fkey eq 'Placemark') ; 
						my $placemark = $$feature{$fkey} ;
						if (${$placemark}{'name'} eq $pmark) {
							my %geometries = %{$$placemark{'MultiGeometry'}} ;
							splice @consolidatedPolygonList,@consolidatedPolygonList,0,@{$geometries{'AbstractGeometryGroup'}} ;
							$found = $fcount ;
							print "found at $found, " ;
							splice @{$featureref[0]}, $found,1 ;
							my $nleft =@{$featureref[0]} ;
							print "$nleft left\n" ;
							last FOUND;
						}
					}
				}
				if ($found == -1){
					die "Couldn't find $pmark!\n" ;
				}
			}
			foreach my $plgn (@consolidatedPolygonList) {
				undef $$plgn{'altitudeMode'} ;
			}
			$newcluster = makeNewClusterFromPlacemark($cn,\@consolidatedPolygonList,$ccn,$cstyle,$description,$cname) ;
		}
		push @newclusters, $newcluster ;
		$newcn++ ; $ccn++ ; 
		#printf("newcn -> $newcn\n") ;
		$styleCounter++ ;
	}
	my $nclusters = @newclusters ;
	print "Adding $nclusters for $cn\n" ; 
	my %newfolder ; 
	my %foldercontainer ;
	makeNewFolder($cn,\@newclusters, \%newfolder, $fdrcnt++) ;
	$foldercontainer{'Folder'} = \%newfolder ;
	push @newfolders, \%foldercontainer ;
	$i++ ;
}
#
# Assign styles to placemarks
#
foreach my $pref (@placemarkhashes) {
	#my $styleid = findInClusters($$pref{'name'},$clusters) ;
	my $styleid ;
	$styleid = $greyid;
	#if ($opt_w && !whiteListed(\@whitelist,$$pref{'name'})) {
	#	$styleid = $greyid ;
	#}
	#else {
	#	#$styleid = $terrainData{$$pref{'name'}}{'terrainType'}%$nc;
	#	$styleid = %styleIdHash{$$pref{'name'}}%$nc;
	#}
	next unless ($styleid != -1) ;

	$$pref{'styleUrl'} = '#TerrainStyle' . sprintf("%.3d",$styleid) ;
#		print "Changing style to $$pref{'styleUrl'}\n" ;
}
#splice @{$featureref[0]},@{$featureref[0]},0,@newclusters ;
#splice @$featuregroup, @$featuregroup, @newfolders ;
{
	my $unassigned = @{$featureref[0]};
	print "$unassigned unassigned (why?)\n" ;
	#if ($opt_w eq "") {
	#	splice @$featuregroup,0,1 ;
	#}
}


{
	unshift @$featuregroup, @newfolders ;
	makeNewFile($data,$opt_k) ;
}
# Split on county basis if we need to
if ($opt_C ne "") {
	if (!(-d $opt_C)) {
		print "ERROR! for County split mode -C should give op directory\n" ;
		exit(5) ;
	}
	foreach my $fder (@newfolders) {
		splice @$featuregroup,0 ;
		unshift @$featuregroup,$fder ;
		my $cname = $$fder{'Folder'}{'name'} ;
		$cname =~ s/\s+/_/g ;
		my $nfname = $opt_C . "/" . $statename . "_" . $cname . ".kml" ;
		print "Writing folder for $nfname" ;
		makeNewFile($data,$nfname) ;
	}
}
#
# printReport
#
printReport(\%countydata,$opt_r,\%terrainData) ;
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
	#	print Dumper $tdata ;
	#return 0;
	open (FREP,">", "$ofile") || die "Can't open $ofile for writing\n" ; 
	print FREP "County,Cluster id,Area (sq.miles), CBG ARea, Holes, %Coverage, Weighted Terrain Code(0-99),Number of Towers, Number of Towers (64QAM and better),Number of Towers (Cluster weighted), Number of Towers (64QAM and better,clusterweighted), List of CBGs\n" ;
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
		for my $aoi (@$listofAois) {
			#print "Name $$aoi{'name'}..." ;
			my $poly = $$aoi{'polygon'} ;
			my $holes = $$aoi{'holes'} ;
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
			my $cbgClusterArea = 0 ; 
			my $cbgClusterHoleArea = 0 ; 
			my $twrs = 0;
			my $twrs2 = 0;
			my $weightedTerrainCode= 0 ;
			my $cbglist = $$clusterlist{$$cid{'name'}} ;
			for my $cbg (@$cbglist) {
				$ostring .= "$cbg:" ;
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
			print FREP "$ostring\n" ;
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
Usage: kmz.pl -f <input kmz file> -k <output kmz file/dir> -r <report file>  -K <Kmeans/proximity/no> -C  (split into county specific files) 
EOH
;
}
