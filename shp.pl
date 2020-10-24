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
use txtKML ;
use Data::Dumper ;
$Data::Dumper::Indent = 1;
my $milesperlat = 69 ;
my $milesperlong = 54.6 ; 
our $opt_f = "" ;
our $opt_w = "" ;
our $opt_K = "proximity3" ;
our $opt_r = "" ;
our $opt_a = "" ;
our $opt_s = "" ;
our $opt_h = 0 ;
our $opt_k = "" ;
my $noclustering = 0;
getopts('s:f:a:r:K:w:hk:') ;

my @polycolors = (0xfffff8dc, 0xffffe4c4, 0xfff5deb3, 0xffd2b48c, 0xff90ed90,0xffadff2f, 0xff32cd32, 0xff228b22) ;
my @solidcolors = (0xff2222ff) ;
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


my @counties ;
my %countydata ;
my %terrainData ;
my @placemarks ;
my %statefolders ;
my @stylegroup;
my $fdrcnt = 0 ;
my %countByState ;

#  note that IDs are 1-based

my $totalArea = 0 ;
my $aoiCtr = 0;
my $skipped = 0;
my @records ;
my $nxt = 0 ;
if ($opt_f =~ /.kml$/) {
	print "Loading kml as txt file\n" ;
	txtKML::loadKMLTxt($opt_f,\@records) ;
}
else {
	my $shapefile = Geo::ShapeFile->new($opt_f, {no_cache => 1});
	printf STDERR "Loaded %d shapes\n",$shapefile->shapes() ;
	print STDERR "Loaded Shapefile!\n" ;
	foreach my $id (1 .. $shapefile->shapes()) {
		my $shape = $shapefile->get_shp_record($id);
# see Geo::ShapeFile::Shape docs for what to do with $shape
		my %db = $shapefile->get_dbf_record($id);
		my $st = $db{'state_abbr'} ;
		my $county = $db{'county'} ;
		$countByState{$st}++ ;
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
		my %rec ;
		$rec{'county'} = $db{'county'} ;
		$rec{'state'} = $db{'state_abbr'} ;
		$rec{'coordinates'} = \@pcoords ;
		$rec{'cbg'} = $db{'cbg_id'} || "None" ;
		$rec{'fid'} = $db{'ORIG_FID'} || "None" ;
		push @records,\%rec ;
	}
}
	
my $nxt = @records ;
my %allowedStates ;
if ($opt_s ne "") {
	print "Allowed states:" ;
	my @sl = split( /[:,]/, $opt_s) ;
	foreach my $s (@sl) {
		$allowedStates{$s} = 1 ;
		print "$s," ;
	}
	print "\n" ;
}

print "Starting processing of records $nxt\n" ;
for (my $i = 0 ; $i<$nxt ; $i++) 
{
	my $thisrec = $records[$i] ;
	my $cpts = @{$$thisrec{'coordinates'}} ;
	printf "[%d/%d] ",$i,$nxt ;
	print "County:$$thisrec{'county'} State:$$thisrec{'state'} CBG:$$thisrec{'cbg'} FIP:$$thisrec{'fid'} $cpts points\n" ; 
	if ($$thisrec{'county'} eq "") { next ; }
	next unless (($opt_s eq "") || defined($allowedStates{$$thisrec{'state'}}))  ;
	#next unless ($$thisrec{'county'} eq "Winston") ;
	if ($opt_w && !whiteListed(\@whitelist,$$thisrec{'county'})) {
		exit(4) ;
		next ;
	}

	my $county = $$thisrec{'state'} . ":". $$thisrec{'county'} ;
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
	$countydata{$county}{'state'} = $$thisrec{'state'} ;
	#
	# Close the pcoords
	# 
	my $coordlist = $$thisrec{'coordinates'} ;
	{
		my @first = @{$$coordlist[0]} ;
		my $nc = @{$coordlist} ; 
		my @last = @{$$coordlist[$nc-1]} ;
		if ($first[0] != $last[0] || $first[1] != $last[1]) {
			splice @$coordlist,@$coordlist - 1, 1, \@first;
		}
	}
	#my $nxtaoi = chainHull_2D @$coordlist ;
	#$nxtaoi->simplify() ;
	my $nxtaoi = Math::Polygon->new(@$coordlist) ;
	print "Initial coord list\n" ;
	my $pcnt = $nxtaoi->nrPoints ;
	my $parea = $nxtaoi->area()*$milesperlat*$milesperlong ;
	$parea -= $holearea ;
	printf "Converted placemark to convex hull of %d points, area = %.4g (closed=%d) ", $pcnt,$parea,$nxtaoi->isClosed() ;
	#next unless ($parea > $EPS) ;
	if (!$nxtaoi->isClosed()) { 
		foreach my $pt (@$coordlist) {
			print "@$pt\n" ;
		}
		print "Polygon is not closed\n" ;
		$skipped++ ; 
		next ; 
	}

	my $center =  $nxtaoi->centroid() ;
	($$cx[$$countyAoiCtr],$$cy[$$countyAoiCtr]) = @$center ;
	my %tdata ; 
	{
			my %histogram ;
			my $npts = int($nxtaoi->area()*$milesperlat*$milesperlong)+1 ;
			print "Calling samplehistogram with $npts points for placemark $$thisrec{'county'}:" ;
			my $spts = $npts*100 ;
			if ($spts > 1200) { $spts = 1200 ; }
			nlcd::sampleHistogram($nxtaoi,$spts,\%histogram) ;
			#my $totalrange = @polycolors ;
			my $tcode = getTerrainCodeFromHistogram(\%histogram,100); 
			$tdata{'terrainType'} = $tcode  ;
			
			print "$tdata{'terrainType'}\n" ;
	}
	$tdata{'area'} = $parea  ;
	$terrainData{$$thisrec{'cbg'}} = \%tdata ;
		
	my $desc = sprintf"%10s\n",$$thisrec{'fid'};
	my @holes ;
	my ($pname,$pid) ;
	$pname = $$thisrec{'cbg'} ;
	$pid = sprintf("ID_%d",$$thisrec{'fid'}) ;
	my $pm = makeNewPlacemark($pname,$nxtaoi,\@holes,"",$pid,$desc) ;
	push @placemarks,$pm;
		
	#print " centroid=$$cx[$$countyAoiCtr],$$cy[$$countyAoiCtr]\n" ; 
	my %aoihash = ( 'name' => $$thisrec{'cbg'} , 'polygon' => \$nxtaoi, 'fid' => $$thisrec{'fid'}) ;
	push @$listofAois,\%aoihash ;
	$totalArea += $parea ;
	$aoiCtr++ ;
}
my $np1 = @placemarks ;
printf "Pushed %d placemarks skipped=%d \n", $np1,$skipped ;
my $tt = 0 ;
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
for my $cname (sort keys %countydata) {
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
foreach my $cn (sort keys %countydata)
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
			print "Default: Trying Proximity clustering for $cn ($sthresh) \n" ;
			($clusters[$nc],$tclusters[$nc]) = 
				aoiClustersProximity($countydata{$cn}{'aois'},$sthresh) ;
		}
	}
	elsif ($opt_K =~ /proximity([.0-9,]+)/) {
		my $thresh = 5 ;
		my @threshvals ;
		$thresh = $1 ;
		my @threshvals = split(/,/,$thresh) ;
		my $bestTwrs = -1 ;
		my $bestThresh = -1 ;
		my ($bestCluster,$bestClLst) ;
		my (@tempcl, @tempClLst) ;
		my @clusterdesc ;
		if (@threshvals == 0) { push @threshvals, $thresh ; }
		{
			print "County $cn: @threshvals\n" ;
			#exit(1) ;
		}
		print "Trying proximity clustering for $thresh, @threshvals!\n" ;
		for (my $tval=0; $tval < @threshvals; $tval++) {
			print "Trying Proximity clustering for $cn (scatter=$threshvals[$tval]) \n" ;
			($tempcl[$tval],$tempClLst[$tval])  = aoiClustersProximity($countydata{$cn}{'aois'},$threshvals[$tval]) ;
			my @clist ;
			my @clusterpoints ;
			splice @clusterdesc,0,@clusterdesc ;
			foreach my $newc (sort keys %{$tempcl[$tval]})
			{
				my @clist = @{$tempcl[$tval]->{$newc}} ;
				my @plist ;
				my @hlist ; 
				my $cliststring = "" ;
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
						print "Couldn't find $pk in data for $counties[$cn]\n" ;
						next ;
					}
		#		if ($pgon == 0) {die "Can't find $pk in list of placemarks\n" ;}
		#			$$pgon->simplify() ;
					my @points = $$pgon->points() ;
					splice @clusterpoints,@clusterpoints,0,@points ;
					push @plist,$$pgon ;
				}
				next if ((@clusterpoints == 0) || (@plist == 0 )) ;
				#my $badclusterpoly = chainHull_2D @clusterpoints ;
				my $badclusterpoly = Math::Polygon->new(@clusterpoints) ;
				my %cinf ;
				$cinf{'name'} = $newc;
				$cinf{'poly'} = $badclusterpoly ;
				push @clusterdesc , \%cinf ;
			}
			my ($T,$T2) = estimateTowersInClusterList(\@clusterdesc,$tempcl[$tval],
						$countydata{$cn}{'aois'},\%terrainData) ;
			if ($T2 < $bestTwrs || $bestTwrs == -1) { 
				$bestCluster = $tempcl[$tval] ;
				$bestClLst = $tempClLst[$tval] ;
				$bestTwrs = $T2 ;
				$bestThresh = $threshvals[$tval] ;
			}
		}
		print "Best thresh for county $cn ($nc)= $bestThresh\n" ;
		$clusters[$nc]=$bestCluster;
		$tclusters[$nc]=$bestClLst ; 
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

#for my $cn (sort keys %countydata) {
#	my $cdata = $countydata{$cn}{'clusterMap'} ;
#	print "Best thresh $cn =>  " ;
#	for my $cn2 (sort keys %$cdata) {
#		my @cl = @{$$cdata{$cn2}} ;
#		print "$cn2 => @cl " ; 
#	}
#}
print "\n" ;

# Prepare the styles
for ($nc = 0; $nc<@polycolors; $nc++){
	print "Adding new style $nc\n" ;
	my %newstyle ;
	my %newst = makeNewSolidStyle($nc,$polycolors[$nc],192,1) ;
	$newstyle{'Style'} = \%newst ;
	push @stylegroup, \%newstyle ;
}
my %clusterst  = makeNewOutlineStyle(0,$solidcolors[0]) ;
my %clusterstyle ;
$clusterstyle{'Style'} = \%clusterst ;
push @stylegroup,\%clusterstyle ;


my $i = 0;
my $newcn = 0;
foreach my $cn (sort keys %countydata)
{
	my @newclusters ;
	my $ccn = 0 ;
	my ($st,$ct) = split(/:/,$cn) ;
	foreach my $newc (sort keys %{$countydata{$cn}{'clusterMap'}}) {
		my @clusterpoints ;
		my @clist = @{$countydata{$cn}{'clusterMap'}{$newc}} ;
		my @plist ;
		my @hlist ; 
		my $cliststring = "" ;
		if ($ct eq "Winston") {
			print "$newc => @{$countydata{$cn}{'clusterMap'}{$newc}}\n" ;
		}
		print "newc = $newc newcn = $newcn\n" ;
		next if (@clist == 0) ;
		for my $pk (@clist){
			my $pgon = 0 ;
			my $preflist = $countydata{$cn}{'aois'};
			$cliststring .= sprintf("%s\n",$pk) ;
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
		#		$$pgon->simplify() ;
			my @points = $$pgon->points() ;
			splice @clusterpoints,@clusterpoints,0,@points ;
			push @plist,$$pgon ;
		}
		next if ((@clusterpoints == 0) || (@plist == 0 )) ;
		my ($badclusterpoly,$clusterpoly) ;
		if (@plist == 1) {
			$badclusterpoly = $plist[0] ; 
			printf "Area = %.4g for %s county %s (no correction required)\n",$badclusterpoly->area()*$milesperlat*$milesperlong, $newc, $cn ;
			$clusterpoly = $badclusterpoly ;
		}
		else {
			$badclusterpoly = Math::Polygon->new(@clusterpoints) ;
			printf "Area = %.4g for %s county %s\n",$badclusterpoly->area()*$milesperlat*$milesperlong, $newc, $cn ;
			$clusterpoly = Math::Polygon->new(cvxPolygon::combinePolygonsConvex(\@plist)) ;
			printf "Area = %.4g for %s county %s (corrected)\n",$clusterpoly->area()*$milesperlat*$milesperlong, $newc, $cn ;
		}
		#printf "Convex operation returns polygon with %d points, closed=%d\n",$clusterpoly->nrPoints(),$clusterpoly->isClosed() ;
		my %options ;
		$options{''} = 1 ;
		#@clusterpoints = $clusterpoly->points() ;
		my %cinf ;
		$cinf{'name'} = $newc;
		$cinf{'poly'} = $clusterpoly ;
		push @{$countydata{$cn}{'clusters'}} , \%cinf ;

		print "Making new cluster from cbglist $cliststring\n" ;
		my $description = makeNewDescription("Cluster $newcn, county $cn List of CBGs:$cliststring\n") ;
		my $cstyle ;
		{
			my $cname ;
			$cstyle = sprintf("TerrainStyle%.3d",$newcn%@polycolors) ;
			# Find the pref and copy it into the cluster data ;
			my @pmarkname = @{$countydata{$cn}{'clusterMap'}{$newc}} ;
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
						#foreach my $pgn (@$pgons) {
						#	my $crdlist = $$pgn{'Polygon'}{'LinearRing'}{'coordinates'} ;
						#	splice @$crdlist,2,@$crdlist - 4 ;
						#}
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
			my $newcluster = makeNewClusterFromPlacemark($ct,\@consolidatedPolygonList,$ccn,$cstyle,$description,$cname) ;
			push @newclusters,$newcluster ;
			my $outlinecluster = makeNewCluster($ct,$clusterpoly,$ccn,"ClusterStyle000","Outline",$cname) ;
			push @newclusters,$outlinecluster ;
		}
		$newcn++ ; $ccn++ ; 
		#printf("newcn -> $newcn\n") ;
	}
	my $nclusters = @newclusters ;
	print "Adding $nclusters placemarks for $cn\n" ; 
	my %newfolder ; 
	my %foldercontainer ;
	if (not defined $statefolders{$st}) {
		my @newfolders ;
		$statefolders{$st} = \@newfolders ;
	}
	makeNewFolder($ct,\@newclusters, \%newfolder, $fdrcnt++) ;
	$foldercontainer{'Folder'} = \%newfolder ;
	push @{$statefolders{$st}}, \%foldercontainer ;
	$i++ ;
}

if ($opt_k ne "") {
	my $dhash ;
	my %tfolder ;
	my ($nstyles,$nfolders) ;
	$nstyles = @stylegroup ;
	my @documents ;
	foreach my $stn (sort keys %statefolders) {
		$nfolders = @{$statefolders{$stn}};
		print "$nstyles styles $nfolders folders\n" ;
		$dhash = makeNewDocument($stn,$statefolders{$stn},\@stylegroup) ;
		#	if ($opt_s eq "") {
		#		$dhash = makeNewDocument("Document",\@newfolders,\@stylegroup) ;
		#push @documents,$dhash;
		#}
		#else {
		#$dhash = makeNewDocument($opt_s,\@newfolders,\@stylegroup) ;
		push @documents,$dhash;
	}
	makeNewDocumentFolder("AllUS",\@documents,\%tfolder) ;
	my %cfolder ;
	$cfolder{'Folder'} = \%tfolder ;
	#	makeNewFile($dhash,$opt_k) ;
	makeNewFile(\%cfolder,$opt_k) ;
}


if ($opt_r ne "") {
	printReport(\%countydata,$opt_r,\%terrainData,$noclustering,0) ;
}
elsif ($opt_a ne "") {
	printReport(\%countydata,$opt_r,\%terrainData,$noclustering,1) ;
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
	print "Thresh = $thresh\nBoxing  " ;
	for (my $aoi=0 ; $aoi < @$aoisref; $aoi++) {
		my %box ;
		$box{'id'} = ${$$aoisref[$aoi]}{'name'} ;
		my $poly =  $$aoisref[$aoi]{'polygon'} ;
		my $cnt = $$poly->centroid ;
		$box{'centroid'} = $cnt ;
		$box{'area'} = $$poly->area * $milesperlat * $milesperlong ;
		print "area=$box{'area'} id=$box{'id'} centroid=@{$box{'centroid'}} " ;
		#printf "Polygon of centroid %.4g,%.4g, area %.4g\n", $$cnt[0], $$cnt[1], $$poly->area ;
		push @boxes,\%box ;
	}
	my $nb = @boxes ;
	print "\nProduced array of size $nb boxes \n" ;
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
	foreach my $cid (sort keys %{$clusters})
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

sub computeTowersPerAoi {
	my $listofAois = shift ;
	my $terrainCode = shift ;
	my $tdata = shift ;
	my %aoiArea ;
	my %aoiHoleArea ;
	my %towers;
	my %towers2;
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
		$$terrainCode{$$aoi{'name'}} = $$tdata{$$aoi{'name'}}{'terrainType'} ;
		{
			my $tc = $$terrainCode{$$aoi{'name'}} ;
			my $cellDensity = 68.24  - 0.166*$tc ;
			my $cellDensity2 = 66.12 - 0.279*$tc ;
			print "$$aoi{'name'}: Terrain code $tc, celldensity=$cellDensity, celldensity2 = $cellDensity2 " ;
			if ($cellDensity2 > $cellDensity) { $cellDensity2 = $cellDensity ; }
			if ($cellDensity == 0 || $cellDensity2 == 0) { die "terrain=$$terrainCode{$$aoi{'name'}} aoi = $$aoi{'name'} density=$cellDensity\n" ; }
			printf "area=%.4g ",($aoiArea{$$aoi{'name'}} - $aoiHoleArea{$$aoi{'name'}}) ;
			my $aoiTower = ((($aoiArea{$$aoi{'name'}} - $aoiHoleArea{$$aoi{'name'}})/$cellDensity)) ;
			$towers{$$aoi{'name'}} += $aoiTower ;

			my $aoiTower2 =((($aoiArea{$$aoi{'name'}} - $aoiHoleArea{$$aoi{'name'}})/$cellDensity2)) ;
			$towers2{$$aoi{'name'}} += $aoiTower2 ;
			print "aoiTower=$aoiTower aoiTower2=$aoiTower2\n" ;
		}
	}
	return (\%aoiArea,\%aoiHoleArea,\%towers,\%towers2,\%fid) ;
}
	
sub estimateTowersInClusterList{
	my $clist = shift ;
	my $clusterlist =  shift ;
	my $listofAois =  shift ;
	my $tdata = shift ;
	my %terrainCode ;
	my $T=0;
	my $T2 = 0;
	my ($aoiArea,$aoiHoleArea,$towers,$towers2,$fid) = computeTowersPerAoi($listofAois,\%terrainCode,$tdata) ;

	for my $cid (@$clist) {
		my $clusterarea = $milesperlat*$milesperlong*$$cid{'poly'}->area() ;
		my $cbgClusterArea = 0 ; 
		my $cbgClusterHoleArea = 0 ; 
		my $twrs = 0;
		my $twrs2 = 0;
		my $weightedTerrainCode= 0 ;
		my $cbglist = $$clusterlist{$$cid{'name'}} ;
		for my $cbg (@$cbglist) {
				$cbgClusterArea += $$aoiArea{$cbg} ; 
				$cbgClusterHoleArea += $$aoiHoleArea{$cbg} ;
				$twrs += $$towers{$cbg};
				$twrs2 += $$towers2{$cbg};
				$weightedTerrainCode += $terrainCode{$cbg}*($$aoiArea{$cbg} - $$aoiHoleArea{$cbg})  ;
				print "$cbg -> $terrainCode{$cbg}, area=$$aoiArea{$cbg} hole=$$aoiHoleArea{$cbg} " ;
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
					$clusterarea, $clusterCellDensity, $clusterCellDensity2;
			print "towers: $ctwrs $ctwrs2, $twrs,$twrs2\n" ;
		}
		my $pc = int(100.0*($cbgClusterArea - $cbgClusterHoleArea)/$clusterarea) ; 
		if ($ctwrs < $twrs) { $twrs = $ctwrs ; }
		if ($ctwrs2 < $twrs2) { $twrs2 = $ctwrs2 ; }
		$T += $twrs ;
		$T2 += $twrs2 ;
	}
	print "Final count:$T $T2\n" ;
	return ($T,$T2) ;
}


# Formula for tower to cell density
# c = 68.24 - 0.166*tc ;
# chigher = 66.12 - 0.279*tc ;
sub printReport{
	my $cdata = shift ;
	my $ofile = shift ;
	my $tdata = shift ;
	my $noclustering = shift ;
	my $appendMode = shift;
	my $state = "Nostate" ;
	if (-e $ofile && ($appendMode == 1)) {
		open (FREP,">>", "$ofile") || die "Can't open $ofile for writing/appending\n" ; 
	}
	else {
		open (FREP,">", "$ofile") || die "Can't open $ofile for writing\n" ; 
		print FREP "State,County,Cluster id,Area (sq.miles), CBG ARea, Holes, %Coverage, Weighted Terrain Code(0-99),Number of Towers, Number of Towers (64QAM and better),Number of Towers (Cluster weighted), Number of Towers (64QAM and better clusterweighted)," ;
		if ($noclustering) {
			print FREP "CBGID,FID\n" ; 
		}
		else {
			print FREP "CBG List,FID List\n" ;
		}
	}


	print "Processing counties..." ;
	my ($totalArea,$totalTowers,$totalTowers2,$totalCbgArea) ;
	$totalArea = $totalTowers = $totalTowers2 = $totalCbgArea = 0 ;
	for my $cname (sort keys %$cdata) {
		my $clist = $$cdata{$cname}{'clusters'} ;
		my $clusterlist = $$cdata{$cname}{'clusterMap'} ;
		my $listofAois = $$cdata{$cname}{'aois'} ;
		$state = $$cdata{$cname}{'state'} ;
		print "....$cname ($state)...." ;
		my ($st,$ct) = split /:/, $cname ;
		if ($ct eq "Winston") {
			foreach my $cid (sort keys %$clusterlist) {
				my @pnamelist = @{$$clusterlist{$cid}} ;
				print "$cid => @pnamelist\n" ;
			}
		}
		my %terrainCode;
		my ($aoiArea,$aoiHoleArea,$towers,$towers2,$fid) = computeTowersPerAoi($listofAois,\%terrainCode,$tdata) ;
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
				if ($fstring eq "") { $fstring .= $$fid{$cbg} ; }
				else { $fstring .= ":".$$fid{$cbg} ; }

				$cbgClusterArea += $$aoiArea{$cbg} ; 
				$cbgClusterHoleArea += $$aoiHoleArea{$cbg} ;
				$twrs += $$towers{$cbg};
				$twrs2 += $$towers2{$cbg};
				$weightedTerrainCode += $terrainCode{$cbg}*($$aoiArea{$cbg} - $$aoiHoleArea{$cbg})  ;
				print "$cbg -> $terrainCode{$cbg}, area=$$aoiArea{$cbg} hole=$$aoiHoleArea{$cbg} " ;
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
			printf FREP "%s,%.10s,%10s,%.6g,%.4g,%.4g,%d%%,%d,%d,%d,%d,%d,",
				$st,
				$ct,$$cid{'name'},
				$clusterarea,$cbgClusterArea,$cbgClusterHoleArea,
				$pc,$weightedTerrainCode,$twrs,$twrs2,$ctwrs,$ctwrs2;
			{ print FREP "$ostring,$fstring\n" ; }

			if ($ctwrs < $twrs) { $twrs = $ctwrs ; }
			if ($ctwrs2 < $twrs2) { $twrs2 = $ctwrs2 ; }
			$totalArea += $clusterarea ;
			$totalCbgArea += $cbgClusterArea ;
			$totalTowers += $twrs ;
			$totalTowers2 += $twrs2 ;
		}
	}
	print "\n";
	#	print FREP "Consolidated: Towers(all coverage) = $totalTowers, Towers(64QAM and better)=$totalTowers2,Area = $totalArea,CBG Area = $totalCbgArea\n" ;
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
