#!/usr/bin/perl

use strict;
use warnings FATAL => qw( all );

my $dir = "/mnt/projects/hdall/data/wig";

chdir($dir);
opendir(D, $dir) or die "ERROR: could not read directory\n";
while (my $f = readdir(D))
{
	next if ($f !~ /bedgraph.gz$/);
	my $wigf = $f;
	$wigf =~ s/bedgraph.gz/music.wig/;
	next if (-s $wigf);
	
	next if ($wigf !~ /_rel/);
	my $cmd = "perl /mnt/projects/hdall/scripts/bedgraph-to-wig.pl $f $wigf";
	print "$cmd\n";
	system("$cmd");
}
closedir(D);