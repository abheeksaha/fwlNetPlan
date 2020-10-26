#!/usr/bin/perl
package KMZ;

require Exporter ;
use strict;
use Geo::KML ;

our @ISA = qw(Exporter);
our @EXPORT = qw(makeNewOutlineStyle makeNewSolidStyle makeNewPolygon makeNewPlacemark makeNewDescription makeNewFolder 
makeNewCluster makeNewDocumentFolder makeNewClusterFromPlacemark makeNewDocument makeNewFile) ; 

sub polygonToArray {
	my $plist = shift ;
	my @pts = @$plist ;
	my @opstr ;
	foreach my $i (@pts) {
		my $pstr ;
		my @xy = @$i ;
		last if (@xy == 0) ;
		$pstr = sprintf "%.10g,%.10g,0.", $xy[0], $xy[1] ;
		push @opstr,$pstr ;
	}
	@opstr ;
}
sub makeNewOutlineStyle{
	my %newst ;
	my $num = shift ;
	my $rgb = shift || -1;
	my $styleid = shift || "ClusterStyle" . sprintf("%.3d", $num) ;
	my ($red,$blue,$green) ;
	if ($rgb == -1) {
		$red = int(rand(255)) ;
		$green = int(rand(255)) ;
		$blue = int(rand(255)) ;
	}
	else {
		$red = ($rgb>>16) & 0xFF ;
		$green = ($rgb>>8) & 0xFF ;
		$blue = ($rgb) & 0xFF ;
	}
	my $clr = (0xff<<24) | (($blue) << 16) | (($green) << 8) | ($red)  ;
	$newst{'id'} = $styleid ;
	#	$newst{'PolyStyle'} = {'color' => $clr, 'outline' => 1, 'fill' => 0} ;
	#$newst{'LabelStyle'} = { 'color' => $clr, 'scale' => 0.0000 } ;
	$newst{'LineStyle'} = { 'color' => $clr, 'width' => 2 } ;
	%newst ;
}
sub makeNewSolidStyle{
	my $num = shift ;
	my $rgb = shift || -1;
	my $transparency = shift  || 255 ;
	my $boundary = shift || 0 ;
	my $styleid = shift || "TerrainStyle" . sprintf("%.3d", $num) ;
	my %newst ;
	my ($red,$blue,$green) ;
	if ($rgb == -1) {
		$red = int(rand(255)) ;
		$green = int(rand(255)) ;
		$blue = int(rand(255)) ;
	}
	else {
		$red = ($rgb>>16) & 0xFF ;
		$green = ($rgb>>8) & 0xFF ;
		$blue = ($rgb) & 0xFF ;
	}
	my $clr = (($transparency%256)<<24) | (($blue) << 16) | (($green) << 8) | ($red)  ;
	my $bwidth = 0;
	if ($boundary) {
		$bwidth= 1.0000 ;
	}
	my $bclr = 0xff0011cc ;
	$newst{'id'} = $styleid ;
	$newst{'PolyStyle'} = {'color' => $clr, 'outline' => 1, 'fill' => 1} ;
	$newst{'LabelStyle'} = { 'color' => $clr, 'scale' => 0.0000 } ;
	$newst{'LineStyle'} = { 'color' => $bclr, 'width' => $bwidth } ;
	%newst ;
}

sub makeNewCluster{
	my $county = shift ;
	my $clusterpoly = shift ;
	my $newcn = shift ;
	my $styleid = shift || sprintf("ClusterStyle%.3d",$newcn) ;
	my $desc = shift || "Empty string\n" ;
	my $cname = shift || sprintf "%s/Cluster_%d",$county,$newcn ;
	my %newcluster ;
	my $polygoncoords  = makeNewPolygon($clusterpoly) ;
	my %placemark ;
	my %polygon ;
	my @polygons ;
	my %line ;
	$placemark{'name'} = $cname . "outline_cluster"; 
	$placemark{'styleUrl'} = "#".$styleid ;
	$placemark{'description'} = $desc; 
	$placemark{'id'} = sprintf("ClusterID_%d_outline",$newcn)  ;

	#$polygon{'outerBoundaryIs'}{'LinearRing'}{'coordinates'} = $polygoncoords ;
	#$polygon{'extrude'} = 0 ;
	my %geom;
	#$geom{'Polygon'} = \%polygon ;
	$line{'coordinates'} = $polygoncoords ;
	$placemark{'LineString'} = \%line ;
	#push @polygons,\%geom ;

	#$placemark{'MultiGeometry'}{'AbstractGeometryGroup'} = \@polygons ;
	#$newcluster{'Placemark'} = \%placemark ;
	$newcluster{'Placemark'} = \%placemark ;
	return \%newcluster ;
}

sub makeNewClusterFromPlacemark{
	my $county = shift ;
	my $cplList = shift ;
	my $newcn = shift ;
	my $styleid = shift || sprintf("ClusterStyle%.3d",$newcn) ;
	my $desc = shift || "Empty string\n" ;
	my $clustername = shift || sprintf "%s/Cluster_%d", $county, $newcn ;
	my %placemark ;
	my %pgroup ;
	my %newcluster ;

	$placemark{'name'} = $clustername ;
	$placemark{'styleUrl'} = "#".$styleid ;
	$placemark{'description'} = $desc; 
	$placemark{'id'} = sprintf("ClusterID_%d",$newcn)  ;
	$pgroup{'AbstractGeometryGroup'} = $cplList ;
	$placemark{'MultiGeometry'} = \%pgroup;
	$newcluster{'Placemark'} = \%placemark ;
	return \%newcluster ;
}

sub makeNewPlacemark{
	my $clustername = shift ;
	my $clusterpoly = shift ;
	my $listofHoles = shift ;
	my $styleid = shift  ;
	my $id = shift ;
	my $desc = shift || "Empty string\n" ;
	my %newplacemark ;
	my $polygoncoords  = makeNewPolygon($clusterpoly) ;
	my %placemark ;
	my %polygon ;
	my @polygons ;
	$placemark{'name'} = $clustername ;
	$placemark{'styleUrl'} = "#".$styleid ;
	$placemark{'description'} = $desc; 
	$placemark{'id'} = $id  ;

	$polygon{'outerBoundaryIs'}{'LinearRing'}{'coordinates'} = $polygoncoords ;
	$polygon{'extrude'} = 0 ;
	my %geom;
	$geom{'Polygon'} = \%polygon ;
	push @polygons,\%geom ;
	if (@$listofHoles) {
		my @holes ;
		my %holegeom ;
		my %innerB ;
		foreach my $hole (@$listofHoles) {
			my %holedesc ;
			my %linearRing ;
			$linearRing{'coordinates'} = makeNewPolygon($hole) ;
			$holedesc{'LinearRing'} = \%linearRing ;
			push @holes,\%holedesc ;
		}
		$innerB{'innerBoundaryIs'} = \@holes ;
		$innerB{'extrude'} = 0 ;
		$holegeom{'Polygon'} = \%innerB ;
		push @polygons,\%holegeom ;
	}
	$placemark{'MultiGeometry'}{'AbstractGeometryGroup'} = \@polygons ;
	$newplacemark{'Placemark'} = \%placemark ;
	return \%newplacemark ;
}

sub makeNewPolygon{
	my $polygon = shift ;
	my @absgrouplists ; 
	my $plist = $polygon->points() ;
	my @pcoords = polygonToArray($plist) ;
	#	my %phashref ;
	#$phashref{'outerBoundaryIs'}{'LinearRing'}{'coordinates'} = \@pcoords ;
	#$phashref{'altitudeMode'} = 'clampToGround' ;
	#$phashref{'extrude'} = 0;
	#%phashref ;
	return \@pcoords ;
}

sub makeNewDescription{
	my $details = shift ;
	if ($details eq "") { $details = sprintf("No Details provided") ; }
my $descstring = sprintf <<EODESC
'<html xmlns:fo="http://www.w3.org/1999/XSL/Format" xmlns:msxsl="urn:schemas-microsoft-com:xslt">
<head>
<META http-equiv="Content-Type" content="text/html">
<meta http-equiv="content-type" content="text/html; charset=UTF-8">
</head>

<body style="margin:0px 0px 0px 0px;overflow:auto;background:#FFFFFF;">
<table style="font-family:Arial,Verdana,Times;font-size:12px;text-align:left;width:100%;border-collapse:collapse;padding:3px 3px 3px 3px">
<tr style="text-align:center;font-weight:bold;background:#9CBCE2">
<td>$details</td>

</tr>
</body>

</html>
EODESC
;
return $descstring ;
}

sub makeNewDocumentFolder {
	my $name = shift ;
	my $listofdocuments = shift ;
	my $folder = shift ;
	$$folder{'name'} = $name ;
	$$folder{'open'} = 1;
	$$folder{'AbstractFeatureGroup'} = $listofdocuments;
}
sub makeNewFolder {
	my $name = shift ;
	my $listofplacemarks = shift;
	my $folder = shift; ;
	my $fdrcount = shift ;
	$name =~ tr/\s+// ;
	$$folder{'name'} = $name ;
	my $num = @$listofplacemarks ;
	print "Making folder $name with $num placemarks\n" ;
	$$folder{'AbstractFeatureGroup'} = $listofplacemarks ;
        $$folder{ 'id'} = sprintf("FeatureLayer%d",$fdrcount) ; $fdrcount++ ;
        $$folder{'description'} = $name ;
	my %snippet ;
	$snippet{'_'} = '' ;
	$snippet{'maxLines'} = 2 ;
	$$folder{'Snippet'} = \%snippet ;
}

sub makeNewDocument {
	my $name = shift ;
	my $flist = shift ;
	my $slist = shift ;
	my %doc ;
	my %details;
	my %snippet ;
	$details{'name'} = $name ;
	$snippet{'maxLines'} = 2 ;
	$details{'Snippet'} = \%snippet ;
	$details{'id'} = $name ;
	$details{'AbstractFeatureGroup'} = $flist ;
	$details{'AbstractStyleSelectorGroup'} = $slist ;
	$doc{'Document'} = \%details ;
	return \%doc ;

}

sub makeNewFile {
	my $data = shift ;
	my $fname = shift ;
	my $opkml = Geo::KML->new(version => '2.2.0') ;
	if ($fname =~ /.*[.]kmz$/) {
		print "Writing to kmz file $fname\n" ;
		$opkml->writeKML($data,$fname,1) ;
	}
	elsif ($fname =~ /.*[.]kml$/) {
		print "Writing to kml file $fname\n" ;
		$opkml->writeKML($data,$fname) ;
	}
	else {
		print "Don't understand file type for $fname\n" ;
	}
}
