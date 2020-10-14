#!/usr/bin/perl
package proximityCluster;

require Exporter ;
use strict;
use Data::Dumper ;
$Data::Dumper::Indent = 1;

our @ISA = qw(Exporter);
our @EXPORT = qw(proximityCluster);

my $milesperlat = 69 ;
my $milesperlong = 54.6 ; 
sub proximityCluster {
	my $boxes = shift ;
	my $thresh = shift ;
	my $nc ;
	my @clusters ;
	do {
		my $boxsize = @$boxes ;
		#print "$boxsize boxes left to place\n" ;
		my $c = findLargest($boxes) ;
		my $centroid = ${$$boxes[$c]}{'centroid'} ;
		#printf "Largest is %s area=%.4g\n",${$$boxes[$c]}{'id'} ,${$$boxes[$c]}{'area'};
		my $cluster = moveToNewCluster(\@clusters,$nc,$c,$boxes) ;
		$nc++ ;
		while (@$boxes) {
		my ($closest,$md) = findClosest($boxes,$centroid) ;
			my $num = @$boxes ;
			#my $closest = int(rand($num)) ;
			#print "\tClosest is ${$$boxes[$closest]}{'id'}\n" ;
			last unless (canAddToCluster($cluster,$$boxes[$closest],$thresh)) ;
			#print "Adding \n" ;
			moveToCluster($cluster,$closest,$boxes) ;
		}
		my $bleft = @$boxes ;
		#print "Finished for this cluster:$bleft\n" ;
	} while (@$boxes) ;
	my %rclusters ;
	for my $cl (@clusters) {
		my $mlist = $$cl{'members'} ;
		my @idlist;
		for my $k (@$mlist) {
			push @idlist, $$k{'id'} ;
		}
		my $cid = $$cl{'id'} ;
		$rclusters{$cid} = \@idlist ;
	}
	return %rclusters ;
}

sub findLargest {
	my $boxes = shift ;
	my $large = 0 ;
	my $np = @$boxes ;
	#print "Testing $np boxes\n";
	for (my $i = 1; $i < $np; $i++) {
		#printf "Comparing (%d) %.4g to (%d) %.4g...\n", $i,${$$boxes[$i]}{'area'}, $large,${$$boxes[$large]}{'area'} ;
		if (${$$boxes[$i]}{'area'} > ${$$boxes[$large]}{'area'}) {
			$large = $i ;
		}
	}
	return $large ;
}

sub findClosest {
	my $boxes = shift ;
	my $centroid = shift ;
	my $nb = @$boxes ;
	my $close = 0 ;
	#print "Find closest\n" ;
	my $mindist = ptDistance(${$$boxes[$close]}{'centroid'},$centroid) ;
	#printf "Find closest: Starting with min distance %.4g (%d to try):",$mindist,$nb ;
	for (my $i = 0; $i < @$boxes; $i++) {
		my $neardist = ptDistance($$boxes[$i]{'centroid'},$centroid);
		if ($neardist < $mindist) {
			$close  = $i ;
			$mindist = $neardist ;
		}
	}
	#print "closest is $close, min dist = $mindist\n" ;
	return $close,$mindist ;
}

sub canAddToCluster {
	my $cluster = shift ;
	my $box = shift ;
	my $thresh = shift;
	my $totalarea =  0 ;
	my @testcluster = @{$$cluster{'members'}} ;
	for (my $i = 0; $i < @testcluster; $i++) {
		my $bx = $testcluster[$i] ;
		$totalarea += $$bx{'area'} ;
	}
	splice @testcluster,@testcluster,0,$box ;
	#print "scatter: canAdd area of cluster=$totalarea\n" ;
	my $newwt = weightedCentroid(\@testcluster) ;
	#printf "scatter: New weighted centroid:%.4g,%.4g->\n",$$newwt[0],$$newwt[1] ;
	#splice @testcluster,-1 ;
	my $newscatter = scatter(\@testcluster,$newwt) ;
	#printf "scatter: new scatter:%.4g, old scatter:%.4g thresh=%.4g\n",$newscatter,$$cluster{'scatter'},$thresh ;
	my $oldscatter = $$cluster{'scatter'} ;
	if ($newscatter < $thresh) {
		#print "can ADD solitary YES\n" ;
		return 1;
	}
	elsif ($newscatter < $oldscatter) {
		#print "can Add YES\n" ;
		return 1 ;
	}
	else {
		#print "can Add NO\n" ;
		return 0 ;
	}
}

sub moveToNewCluster {
	my $clusters = shift ;
	my $nc = shift ;
	my $cid = shift;
	my $boxes = shift ;
	my %newcluster ;
	my @members ;
	my @b = @$boxes ;
	#print "Making new cluster\n" ;
	push @members, $b[$cid] ;
	$newcluster{'members'} = \@members ;
	$newcluster{'centroid'} = weightedCentroid(\@members) ;
	my $cname = sprintf("cluster%.3d",$nc) ;
	$newcluster{'id'} = $cname ;
	my @newcentroid = @{$newcluster{'centroid'}} ;
	$newcluster{'scatter'} = scatter(\@members,$newcluster{'centroid'}) ;
	#print "Scatter computed for new cluster:$newcluster{'scatter'}\n" ;
	push @$clusters , \%newcluster ;
	my $last = $#b ;
	#printf "Moving %d from box of size %d \n", $cid, $last+1 ;
	for (my $i = $cid; $i<$last ; $i++) {
		$$boxes[$i] = $$boxes[$i+1] ;
	}
	splice(@$boxes,-1) ;
	my $left = @$boxes ;
	#printf "Moved box %s to cluster %s (%d left)\n", ${$members[0]}{'id'}, $cname,$left ;
	return \%newcluster ;
}


sub moveToCluster{
	my $cluster = shift ;
	my $cid = shift;
	my $boxes = shift ;
	#print "Moving $cid to the existing cluster $$cluster{'id'} \n",$cid ;
	push @{$$cluster{'members'}} , $$boxes[$cid] ;
	$$cluster{'centroid'} = weightedCentroid($$cluster{'members'}) ;
	$$cluster{'scatter'} = scatter($$cluster{'members'},$$cluster{'centroid'}) ;
	my @b = @$boxes ;
	my $last = $#b ;
	for (my $i = $cid; $i<$last ; $i++) {
		$$boxes[$i] = $$boxes[$i+1] ;
	}
	splice(@$boxes,@$boxes-1,1) ;
	my $left = @$boxes ;
	my @list = @{$$cluster{'members'}} ;
	#printf "Moved box %s to existing cluster %s (%d left)\n", $list[$#list]{'id'}, $$cluster{'id'},$left ;
}

#
# Utility functions
#
sub ptDistance {
	my $wx1 = shift ;
	my $wx2 = shift ;
	#printf "ptDistance: %.4g:%.4g  to %.4g:%.4g:",$$wx1[0],$$wx1[1], $$wx2[0],$$wx2[1] ;
	my $dist = sqrt((($milesperlat*($$wx1[0] - $$wx2[0]))**2.0) + ($milesperlong*($$wx1[1] - $$wx2[1]))**2.0) ;
	#print "$dist\n" ;
	return $dist;
}

sub weightedCentroid {
	my $cluster = shift ;
	my ($np,$tw) ;
	my @txy ;
	$txy[0] = $txy[1] = $np = $tw = 0;
	for my $box (@$cluster) {
		my $area = $$box{'area'} ; 
		my $centroid = $$box{'centroid'} ;
		#print "Adjusting for $$centroid[0], $$centroid[1] area=$area\n" ;
		$txy[0] += $$centroid[0]*$area ;
		$txy[1] += $$centroid[1]*$area ;
		$tw += $area ;
		$np++ ;
	}
	if ($tw != 0) { 
	$txy[0] = $txy[0]/($tw) ;
	$txy[1] = $txy[1]/($tw) ;
	}
	#printf "Weighted Centroid:%.4g %.4g\n",$txy[0],$txy[1] ;
	return \@txy ;
}

sub scatter {
	my $members  = shift ;
	my $centroid = shift ;
	my @dist ;
	my $tdist = 0;
	my $tarea = 0;
	my $i;
	#print "Entering scatter: centroid $$centroid[0] $$centroid[1]\n" ;
	my @memberlist = @$members ;
	for ( $i = 0; $i < @memberlist; $i++) {
		my $member = $memberlist[$i] ;
		my $ccent = $$member{'centroid'} ;
		my $area = $$member{'area'} ;
		$dist[$i] = ptDistance($ccent,$centroid) - sqrt($area*114/355.0) ;
		#printf "area = %.4g", $area ;
		if ($dist[$i] > 0) { $tdist += $dist[$i] ; }
		$tarea += $area ;
	}
	#print "tdist=$tdist: i=$i tarea=$tarea " ;
	if ($i == 0) { 
	#print "\n" ; 
	return 0 ; }
	else { 
		my $sctr = $tdist/$i;
		#		printf "Final scatter =%.4g\n",$sctr;
		return $sctr;
	} 
}
