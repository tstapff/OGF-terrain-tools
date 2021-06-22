#! /usr/bin/perl -w -CSDA

use strict;
use warnings;
use LWP::Simple;
use OGF::Util::Usage qw( usageInit usageError );

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

my $BASE = 'https://opengeofiction.net';
my $API  = "$BASE/api/0.6";

my %opt;
usageInit( \%opt, qq/ h start=i end=i full /, << "*" );
[-start <userid> -end <userid> -full]

-start   start list at this user id (default     0)
-end     end list at this user id   (default 30000)
-full    include users with 0 changesets
*
usageError() if $opt{'h'};
my $START_ID = $opt{'start'} ||     0;
my $END_ID   = $opt{'end'}   || 30000;
my $FULL     = $opt{'full'} ? 1 : 0;
print STDERR "Users: $START_ID > $END_ID\n";

print "id,name,link,created,latest,admin,mod,changesets,blocks,blocks_active,blocked,blocked_active\n";
my $last_id = undef;
for( my $userid = $START_ID; $userid <= $END_ID; $userid++ )
{
	# the OGF server API doesn't support the "users" request, so one at a time...
	my $url = "$API/user/$userid";
	
	my $content = get($url);
	if( defined $content )
	{
		my $id             = '';
		my $name           = '';
		my $profile        = '';
		my $created        = '';
		my $latest         = '';
		my $admin          = 'N';
		my $mod            = 'N';
		my $changesets     = 0;
		my $blocks         = 0;
		my $blocks_active  = 0;
		my $blocked        = 0;
		my $blocked_active = 0;
		foreach my $line ( split "\n", $content )
		{
			# poor man's XML parsing, too many Perl years 
			if( $line =~ /<user id=\"(\d+)\" display_name=\"(.+)\" account_created=\"([\d\-TZ\:]+)\">/ )
			{
				$id      = $1;
				$name    = $2;
				$profile = "$BASE/user/$name";
				$created = $3;
			}
			$admin      = 'Y' if( $line =~ /<administrator\/>/ );
			$mod        = 'Y' if( $line =~ /<moderator\/>/ );
			$changesets = $1  if( $line =~ /<changesets count=\"(\d+)\"\/>/ );
			if( $line =~ /<received count=\"(\d+)\" active="(\d+)\"\/>/ )
			{
				$blocks = $1;
				$blocks_active = $2;
			}
			if( $line =~ /<issued count=\"(\d+)\" active="(\d+)\"\/>/ )
			{
				$blocked = $1;
				$blocked_active = $2;
			}
		}
		if( defined $id )
		{
			$last_id = $id;
			
			# get last edit by the user
			my $url = "$API/changesets?user=$id";
			my $content = get($url);
			if( defined $content )
			{
				foreach my $line ( split "\n", $content )
				{
					if( $line =~ /closed_at=\"([\d\-TZ\:]+)\"/ )
					{
						$latest = $1;
						last;
					}
				}
			}
			next if( $FULL == 0 and $changesets == 0 );
			print "$id,$name,$BASE/user/$name,$created,$latest,$admin,$mod,$changesets,$blocks,$blocks_active,$blocked,$blocked_active\n";
			my $block = '';
			$block = 'b' if( $blocks > 0 );
			$block = 'B' if( $blocks_active > 0 );
			printf STDERR "$id: %-55s %20s %3d %s\n", $profile, $latest, $changesets, $block;
		}
	}
}
print STDERR "$last_id\n" if( defined $last_id );

