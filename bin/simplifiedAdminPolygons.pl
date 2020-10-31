#! /usr/bin/perl -w

use lib '/opt/osm/perl5';
use strict;
use warnings;
use JSON::PP;
use URI::Escape;
use Date::Format;
use OGF::Geo::Topology;
use OGF::Util::File;
use OGF::Util::Line;
use OGF::Data::Context;
use OGF::View::TileLayer;
use OGF::Util::Usage qw( usageInit usageError );


# perl C:/usr/OGF-terrain-tools/bin/simplifiedAdminPolygons.pl
# perl C:/usr/OGF-terrain-tools/bin/simplifiedAdminPolygons.pl -od /home/lkind/ogf
# perl C:/usr/OGF-terrain-tools/bin/simplifiedAdminPolygons.pl -ds Roantra

my %opt;
usageInit( \%opt, qq/ h ogf ds=s od=s /, << "*" );
[-ogf] [-ds <dataset>] [-od <output_directory>]

-ogf    use ogfId as key
-ds     "Roantra", "AN134cd" or empty
*

my( $osmFile ) = @ARGV;
usageError() if $opt{'h'};


my $OUTPUT_DIR = $opt{'od'} || 'C:/usr/MapView/tmp';
my( $aTerr, $COMPUTATION_ZOOM, $OUTFILE_NAME, $ADMIN_RELATION_QUERY );
our $URL_TERRITORIES = 'https://wiki.opengeofiction.net/wiki/index.php/OGF:Territory_administration?action=raw';

if( ! $opt{'ds'} ){
    $aTerr = getTerritories();
    $COMPUTATION_ZOOM = 6;
    $OUTFILE_NAME = 'ogf_polygons';
    $ADMIN_RELATION_QUERY = << '---EOF---';
[timeout:1800][maxsize:4294967296];
(
  (relation["boundary"="administrative"]["admin_level"="2"];
   relation["boundary"="administrative"]["ogf:id"~"^((UL|TA|AN|AR|ER|KA|OR|PE)[0-9]{3}[a-z]?|(AR050|AR120|UL106|AR001b)-[0-9]{2}|AR120-3[23][a-z]|AR120-31a|AR045-(02|04|06|08|09|11|12|13)|AR045-(01|03|05|07|10)[a-z]|UL[0-9]{2}[a-z]+)$"];);
  >;
);
out;
---EOF---

}elsif( $opt{'ds'} eq 'Roantra' ){
    $aTerr = [];
    $COMPUTATION_ZOOM = 12;
    $OUTFILE_NAME = 'polygons';
    $ADMIN_RELATION_QUERY = << '---EOF---';
[timeout:1800][maxsize:4294967296];
(
  (relation["land_area"="administrative"]["ogf:area"~"^RO\\."];
   relation["boundary"="administrative"]["ogf:area"~"^RO\\."];);
  >;
);
out;
---EOF---

}elsif( $opt{'ds'} eq 'AN134cd' ){
	$URL_TERRITORIES = 'https://wiki.opengeofiction.net/wiki/index.php/OGF:Territory_administration/AN134cd?action=raw';
    $aTerr = getTerritories();
    $COMPUTATION_ZOOM = 6;
    $OUTFILE_NAME = 'ogf_polygons_AN134cd';
    $ADMIN_RELATION_QUERY = << '---EOF---';
[timeout:1800][maxsize:4294967296];
(
  (relation["boundary"="administrative"]["ogf:id"~"^AN134[cd]$"];);
  >;
);
out;
---EOF---

}else{
    die qq/Unknown dataset: "$opt{ds}"/;
}


if( ! $osmFile ){
	$osmFile = 'C:/usr/MapView/tmp/admin_polygons_'. time2str('%y%m%d_%H%M%S',time) .'.osm';
	$osmFile = $OUTPUT_DIR . '/admin_polygons_'. time2str('%y%m%d_%H%M%S',time) .'.osm';
    fileExport_Overpass( $osmFile ) if ! -f $osmFile;
}


my $tl = OGF::View::TileLayer->new( "image:OGF:$COMPUTATION_ZOOM:all" );
my( $proj ) = $tl->{_proj};

my $ctx = OGF::Data::Context->new();
$ctx->loadFromFile( $osmFile );
$ctx->setReverseInfo();

#my $relKey = $opt{'ogf'} ? $rel->{'tags'}{'ogf:id'} : $rel->{'id'};
#die qq/Relation $rel->{id} doesn't have an ogf:id\n/ if ! $relKey;

our %VERIFY_IGNORE = (
#   481   => 'UL130',   # Alora, Takora region (indyroads); no problem
#   10386 => 'TA333',   # Egani, southern islands; deleted by isleño
#   24874 => 'PE070',   # ???; deleted by Luciano
#   21935 => 'TA113d',  # Ajanjo, part of San Marcos (sude)
#   43801 => 'UL111',   # deleted by Stjur
#   43803 => 'UL115',   # deleted by Stjur
#   61490 => 'TA114a',  # Kesland Islands, Antigo nuclear base; no problem
#   91121 => 'AR120-00',# AR120 capital region, missing ogf:id; no problem
    179507 => 'AN134c', # problematic relation, "polygon not closed" but is?
    179506 => 'AN134d', # problematic relation, "polygon not closed" but is?
);

my $hSharedBorders = {};

foreach my $way ( values %{$ctx->{_Way}} ){
	my @rel = sort keys %{$ctx->{_rev_info}{$way->uid}};
	my $key = join( ':', @rel );
	
	my $num = scalar( @rel );
	if( !($num == 1 || $num == 2) ){
		print STDERR "\$key <", $key, ">\n";  # _DEBUG_
		warn qq/Error: way $way->{id} is element of $num relations\n/;
	}

	$hSharedBorders->{$key} = [] if ! $hSharedBorders->{$key};
	push @{$hSharedBorders->{$key}}, $way->{'id'};
}

writeRegionInfo( $ctx, $OUTPUT_DIR . '/admin_regions.json' );


foreach my $avwThreshold ( 50, 100, 200, 400, 800, 1600, 3200 ){

    my $ctx3 = OGF::Data::Context->new();
    $ctx3->{_Node} = $ctx->{_Node};
    my $ct = 0;

    foreach my $key ( keys %$hSharedBorders ){
        my @relIds = map {substr($_,2)} split( /:/, $key );
        my $aSegments = $hSharedBorders->{$key};

        my $ctx2 = OGF::Data::Context->new( $proj );
        map {$ctx2->{_Way}{$_} = $ctx->{_Way}{$_}} @$aSegments;

        my $aConnected = OGF::Geo::Topology::buildWaySequence( $ctx2, undef, undef, {'copy' => 1} );
#    	  use Data::Dumper; local $Data::Dumper::Indent = 1; local $Data::Dumper::Maxdepth = 4; print STDERR Data::Dumper->Dump( [$aConnected], ['aConnected'] ), "\n";  # _DEBUG_

        foreach my $way ( @$aConnected ){
#    		    my @points = map {[$_->{'lon'},$_->{'lat'}]} map {$ctx->{_Node}{$_}} @{$way->{'nodes'}};
            my @points = map {$proj->geo2cnv($_)} map {[$_->{'lon'},$_->{'lat'}]} map {$ctx->{_Node}{$_}} @{$way->{'nodes'}};
            print STDERR "way: ", $way->{'id'}, "  ogfId: ", ($way->{'tags'}{'ogf:id'} || ''), "  size: ", $#points, "\n";  # _DEBUG_
#    		    use Data::Dumper; local $Data::Dumper::Indent = 1; local $Data::Dumper::Maxdepth = 3; print STDERR Data::Dumper->Dump( [\@points], ['*points'] ), "\n";  # _DEBUG_
            my $aIndex = OGF::Util::Line::algVisvalingamWhyatt( \@points, {'indexOnly' => 1, 'threshold' => $avwThreshold} );
            @{$way->{'nodes'}} = map {$way->{'nodes'}[$_]} @$aIndex;

            my $wayId = --$ct;
            $way->{'id'} = $wayId;
            $ctx3->{_Way}{$wayId} = $way;

            foreach my $relId ( @relIds ){
                addWayToRelation( $ctx3, $relId, $way );
            }
        }
    }

    my $hPolygons = {};
    foreach my $rel ( values %{$ctx3->{_Relation}} ){
        print STDERR "* rel ", $rel->{'id'}, " ", scalar(@{$rel->{'members'}}) ,"\n";  # _DEBUG_
        my $aRelOuter = $rel->closedWayComponents( 'outer' );
        my @polygon;
        foreach my $way ( @$aRelOuter ){
            print STDERR "  * way ", $way->{'id'}, "\n";  # _DEBUG_
            my $aRect = $way->boundingRectangle( $ctx3, $proj );
            my $rectArea = abs($aRect->[2] - $aRect->[0]) * abs($aRect->[3] - $aRect->[1]);
#           next if $rectArea < $avwThreshold;
#           my @points = map {[0+$_->{'lat'},0+$_->{'lon'}]} map {$ctx3->{_Node}{$_}} @{$way->{'nodes'}};
            my @points;
            foreach my $nodeId ( @{$way->{'nodes'}} ){
                my $node = $ctx3->{_Node}{$nodeId};
                if( ! $node ){
                    print STDERR "  invalid node $nodeId (possible Overpass problem)\n";
                    next;
                }
                push @points, [ 0+$node->{'lat'}, 0+$node->{'lon'} ];
            }
#    		    use Data::Dumper; local $Data::Dumper::Indent = 1; local $Data::Dumper::Maxdepth = 3; print STDERR Data::Dumper->Dump( [\@points], ['*points'] ), "\n";  # _DEBUG_
            push @polygon, {_rectArea => $rectArea, _points => \@points};
        }

        # make sure the largest way is always preserved, however small
        @polygon = sort {$b->{_rectArea} <=> $a->{_rectArea}} @polygon;
        for( my $i = 1; $i <= $#polygon; ++$i ){
            $polygon[$i] = undef if $polygon[$i]->{_rectArea} < $avwThreshold;
        }
        @polygon = map {$_->{_points}} grep {defined} @polygon;
        @polygon = @{$polygon[0]} if scalar(@polygon) == 1;

		my $relKey = $rel->{'id'};
		if( $opt{'ogf'} ){
			$relKey = $ctx->{_Relation}{$relKey}{'tags'}{'ogf:id'};
		}
#		die qq/Unexpected error: no relation key (rel=$rel->{id})\n/ if ! $relKey;
		if( ! $relKey ){
			warn qq/Unexpected error: no relation key (rel=$rel->{id})\n/;
			next;
		}
        $hPolygons->{$relKey} = \@polygon;
    };

    if( $avwThreshold == 100 ){
        my $aErrors = verifyTerritories( $hPolygons, $aTerr );
        if( @$aErrors ){
            use Data::Dumper; local $Data::Dumper::Indent = 1; local $Data::Dumper::Maxdepth = 3; print STDERR Data::Dumper->Dump( [$aErrors], ['aErrors'] ), "\n";  # _DEBUG_
            exit;
        }
    }

    my $json = JSON::PP->new->indent(2)->space_after;
#   writePolygonJson( "C:/usr/MapView/tmp/${OUTFILE_NAME}_${avwThreshold}.json", $hPolygons );
    writePolygonJson( "$OUTPUT_DIR/${OUTFILE_NAME}_${avwThreshold}.json", $hPolygons );
}





#-------------------------------------------------------------------------------




sub verifyTerritories {
    my( $hPolygons, $aTerritories ) = @_;
    my @errors;
    foreach my $hTerr ( @$aTerritories ){
        my( $ogfId, $relId ) = ( $hTerr->{'ogfId'}, $hTerr->{'rel'} );
        my $errText;
        if( $hPolygons->{$relId} ){
            $errText = verifyPolygon( $hPolygons->{$relId} );
        }else{
	        $errText = 'Missing polygon';
		}
        print STDERR $ogfId;
        if( $errText ){
            print STDERR " ", $errText;
			
            unless( $VERIFY_IGNORE{$relId} ) {
				my $err = {
					_ogfId => $ogfId,
					_rel   => $relId,
					_text  => $errText,
				};
				push @errors, $err;
			}
        }
        print STDERR "\n";
    }
    return \@errors;
}

sub writeRegionInfo {
    my( $ctx, $outFile ) = @_;
#   my %rtags = ('AN' => 'Antarephia', 'TA' => 'Tarephia', 'AR120' => 'South Archanta', 'UL106' => 'East Uletha');
    my %rtags = ('AN' => 'Antarephia', 'TA' => 'Tarephia');
    my %regionInfo;
    foreach my $hRel ( values %{$ctx->{_Relation}} ){
        my( $ogfId, $region ) = ( $hRel->{'tags'}{'ogf:id'}, $hRel->{'tags'}{'is_in:continent'} );
        next if( !defined $ogfId );
		if( ! $region ){
#           my( $rtag ) = ($ogfId =~ /^([A-Z]{2}(?:106|120)?)/g);
            my( $rtag ) = ($ogfId =~ /^([A-Z]{2})/g);
            $region = $rtags{$rtag} if $rtag && $rtags{$rtag};
            $region = 'South Archanta' if $ogfId =~ /^AR120-3[23][a-z]/;
            $region = 'North Archanta' if $ogfId =~ /^AR001b-/;
        }
#       push @regionInfo, {
#           'rel'    => $hRel->{'id'},
#           'ogfId'  => $ogfId,
#           'region' => $region,
#       };
        $regionInfo{$hRel->{'id'}} = $region if $region;
    }

    my $json = JSON::PP->new->indent(2)->space_after;
    my $text = $json->encode( \%regionInfo );
    OGF::Util::File::writeToFile( $outFile, $text, '>:encoding(UTF-8)' );
}


sub verifyPolygon {
    my( $aPol ) = @_;
    my $errText = '';
    my $p0 = $aPol->[0][0];
    return 'Empty Polygon' if ! $p0;
    if( ref($p0) ){
        foreach my $aP ( @$aPol ){
            my $err2 = verifyPolygon( $aP );
            $errText .= $err2 . "\n" if $err2;
        }
    }else{
        my( $x0, $y0, $x1, $y1 ) = ( $aPol->[0][0], $aPol->[0][1], $aPol->[-1][0], $aPol->[-1][1] );
        $errText = ($x0 == $x1 && $y0 == $y1)? '' : 'Polygon not closed';
    }
    return $errText;
}




sub addWayToRelation {
	my( $ctx3, $relId, $way ) = @_;
	if( ! $ctx3->{_Relation}{$relId} ){
		OGF::Data::Relation->new( $ctx3, {'id' => $relId} );
	}
	$ctx3->{_Relation}{$relId}->add_member( 'outer', $way );
}


# relation["boundary"="administrative"]["admin_level"="2"]["ogf:id"="UL202"];

sub fileExport_Overpass {
	require OGF::Util::Overpass;
	my( $outFile ) = @_;
#   relation["boundary"="administrative"]["admin_level"="2"];

#    my $data = OGF::Util::Overpass::runQuery_remote( undef, << '    ---EOF---' );
#       [timeout:1800][maxsize:4294967296];
#       (
#         (relation["boundary"="administrative"]["admin_level"="2"];
#          relation["boundary"="administrative"]["ogf:id"~"^((UL|TA|AN|AR|ER|KA|OR|PE)[0-9]{3}[a-z]?|AR120-[0-9]{2})$"];);
#         >;
#       );
#       out;
#    ---EOF---
    my $data = OGF::Util::Overpass::runQuery_remote( undef, $ADMIN_RELATION_QUERY );
	OGF::Util::File::writeToFile( $outFile, $data, '>:encoding(UTF-8)' );
}

sub getTerritories {
    require LWP;

    my $json = JSON::PP->new();
	my $userAgent = LWP::UserAgent->new(
		keep_alive => 20,
	);

	my $resp = $userAgent->get( $URL_TERRITORIES );
    my $aTerr = $json->decode( $resp->content() );
#	use Data::Dumper; local $Data::Dumper::Indent = 1; local $Data::Dumper::Maxdepth = 3; print STDERR Data::Dumper->Dump( [$aTerr], ['aTerr'] ), "\n";  # _DEBUG_

    return $aTerr;
}


sub writePolygonJson {
	my( $filePoly, $hPolygons ) = @_;
    local *OUTFILE;
    open( OUTFILE, '>:encoding(UTF-8)', $filePoly ) or die qq/Cannot open "$filePoly" for writing: $!\n/;
    my $jsonP = JSON::PP->new;
    print OUTFILE "{\n";
    my @keyList = sort keys %$hPolygons;
    my $ccP = lastLoop( \@keyList, ',', '' );
    foreach my $key ( @keyList ){
        if( ref($hPolygons->{$key}[0][0]) ){
            my $ccPP = lastLoop( $hPolygons->{$key}, ',', '' );
            print OUTFILE qq/"$key": [\n/;
            foreach my $aP ( @{$hPolygons->{$key}} ){
                print OUTFILE "  ", $jsonP->encode($aP), $ccPP->(), "\n";
            }
            print OUTFILE "]", $ccP->(), "\n";
        }else{
            print OUTFILE qq/"$key": /, $jsonP->encode($hPolygons->{$key}), $ccP->(), "\n";
        }
    }
    print OUTFILE "}\n";
    close OUTFILE;
}

sub lastLoop {
	my( $aList, $str, $strLast ) = @_;
	my $num = scalar( @$aList );
	my $cSub = sub {
		return --$num ? $str : $strLast;
	};
	return $cSub;
}




