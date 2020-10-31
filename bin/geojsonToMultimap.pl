#! /usr/bin/perl -w
# Convert GeoJSON to Multimaps

use strict;
use warnings;
use JSON;
use Data::Dumper;

sub update_limits($$);

# check command line
if( @ARGV != 1 )
{
	print <<USAGE;
Convert a GeoJSON file output by JOSM into the OGF Mutimaps formatting, suitable for use on a wiki map
https://wiki.opengeofiction.net/wiki/index.php/OGF:Using_the_MultiMaps_extension

Features in the GeoJSON should be have the following properties:
 ogf:title
 ogf:text or name
 ogf:color
 ogf:weight
 ogf:opacity
 ogf:fillcolor
 ogf:fillopacity
 ogf:radius
These map directly to the vaules for the Circle, Line and Polygon Multimaps definitions

The following can also be set:
 ogf:order - lower values are output first, duplicates sorted by their lat:lon
 ogf:type  - set to polygon to workaround JOSM sometimes outputting polygons as lines
 
USAGE:
 $0 file.geojson > output.txt
USAGE
	exit 1;
}
my $filename = $ARGV[0];
die "file does not exist" unless( -f $filename );

# load JSON file into a string
my $json;
{
	local $/; 
	open my $fh, "<", "lonowai.geojson";
	$json = <$fh>;
	close $fh;
}

# decode the JSON
my $decoded = decode_json $json;
#print Dumper($decoded);

my %limits = (minlat => undef, minlon => undef, maxlat => undef, maxlon => undef);
my %output = ();

# loop round each feature defined
for my $ob ( @{$decoded->{features}} )
{
	# metadata
	my $order       = (defined $ob->{properties}{'ogf:order'})       ? $ob->{properties}{'ogf:order'}       : 25;
	my $type        = (defined $ob->{properties}{'ogf:type'})        ? $ob->{properties}{'ogf:type'}        : undef;
	# values
	my $title       = (defined $ob->{properties}{'ogf:title'})       ? $ob->{properties}{'ogf:title'}       : 'unknown';
	my $text        = (defined $ob->{properties}{'ogf:text'})        ? $ob->{properties}{'ogf:text'}        : (defined $ob->{properties}{'name'}) ? $ob->{properties}{'name'} : 'unknown';
	my $color       = (defined $ob->{properties}{'ogf:color'})       ? $ob->{properties}{'ogf:color'}       : 'black';
	my $weight      = (defined $ob->{properties}{'ogf:weight'})      ? $ob->{properties}{'ogf:weight'}      : '1';
	my $opacity     = (defined $ob->{properties}{'ogf:opacity'})     ? $ob->{properties}{'ogf:opacity'}     : '1';
	my $fillcolor   = (defined $ob->{properties}{'ogf:fillcolor'})   ? $ob->{properties}{'ogf:fillcolor'}   : 'white';
	my $fillopacity = (defined $ob->{properties}{'ogf:fillopacity'}) ? $ob->{properties}{'ogf:fillopacity'} : '1';
	my $radius      = (defined $ob->{properties}{'ogf:radius'})      ? $ob->{properties}{'ogf:radius'}      : '100';

	# Handle Point type and Circles
	if( $ob->{geometry}{type} eq "Point" )
	{
		my $coords = sprintf "%.5f,%.5f", $ob->{geometry}->{coordinates}[1], $ob->{geometry}->{coordinates}[0];
		my $key    = sprintf "%02d-$coords", $order;
		
		update_limits $ob->{geometry}->{coordinates}[1], $ob->{geometry}->{coordinates}[0];
			
		#| Circle = Coordinates : radius ~ Title ~ Text ~ Color ~ Weight ~ Opacity ~ FillColor ~ FillOpacity ~ Fill
		$output{$key} = "| Circle = $coords:$radius~Title=$title ~Text=$text ~Color=$color ~Weight=$weight ~Opacity=$opacity ~FillColor=$fillcolor ~FillOpacity=$fillopacity\n";
	}
	# handle LineString and Polygon types
	elsif( ($ob->{geometry}{type} eq "LineString") or ($ob->{geometry}{type} eq "Polygon") )
	{
		# JOSM has a habit of outputting polygons as LineString - specify ogf:type=polygon to force
		my $ispoly = 'no';
		$ispoly = 'real' if( $ob->{geometry}{type} eq "Polygon" );
		$ispoly = 'fake' if( ($ob->{geometry}{type} eq "LineString") and (defined $type and $type eq "polygon") );
		
		my $coords = $ob->{'geometry'}->{'coordinates'};
		$coords = @$coords[0] if( $ispoly eq 'real' );
		my $key = undef;
		my $sep = '';
		foreach my $coord (@$coords)
		{
			if( !defined $key )
			{
				$key = sprintf "%02d-%.5f,%.5f", $order, $coord->[1], $coord->[0];
				$output{$key} = ($ispoly ne 'no') ? "| Polygon = " : "| Line = ";
			}
			$output{$key} .= sprintf "%s%.5f,%.5f", $sep, $coord->[1], $coord->[0];
			$sep = ':';
			update_limits $coord->[1], $coord->[0];
		}

		if( $ispoly ne 'no' )
		{
			#| Polygon = Coordinates : Coordinates2 : Coordinates3 [: Coordinates 4 etc.…] ~ Title ~ Text ~ Color ~ Weight ~ Opacity ~ FillColor ~ FillOpacity ~ Fill
			$output{$key} .= "~Title=$title ~Text=$text ~Color=$color ~Weight=$weight ~Opacity=$opacity ~FillColor=$fillcolor ~FillOpacity=$fillopacity\n";
		}
		else
		{
			#| Line = Coordinates : Coordinates2 [: Coordinates3 : Coordinates 4 etc.…] ~ Title ~ Text ~ Color ~ Weight ~ Opacity
			$output{$key} .= "~Title=$title ~Text=$text ~Color=$color ~Weight=$weight ~Opacity=$opacity\n";
		}
		
	}
}

# output the multmaps header
my $lat = sprintf "%.3f", (defined $limits{minlat}) ? ($limits{minlat} + $limits{maxlat}) / 2.0 : 0;
my $lon = sprintf "%.3f", (defined $limits{minlon}) ? ($limits{minlon} + $limits{maxlon}) / 2.0 : 0;
print <<EOF;
{{#multimaps:
| center = $lat,$lon
| width = 100%
| height = 500px
| zoom = 10
| maxzoom = 19
| minzoom = 6
EOF

# output each feature, sorted by the order and first lat:lon
foreach my $key ( sort keys %output )
{
	print $output{$key};
}

# output multimaps footer
print <<EOF;
}}
EOF

exit 0;


sub update_limits($$)
{
	my($lat, $lon) = @_;
	$limits{minlat} = $lat if( !defined $limits{minlat} or $lat < $limits{minlat} );
	$limits{minlon} = $lon if( !defined $limits{minlon} or $lon < $limits{minlon} );
	$limits{maxlat} = $lat if( !defined $limits{maxlat} or $lat > $limits{maxlat} );
	$limits{maxlon} = $lon if( !defined $limits{maxlon} or $lon > $limits{maxlon} );
}
