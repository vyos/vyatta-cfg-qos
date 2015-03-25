#!/usr/bin/perl
#
# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2009 Vyatta, Inc.
# All Rights Reserved.
#
# Author: Stephen Hemminger
# Date: March 2009
# Description: Script to automatically generate per-interface qos templates.
#
# **** End License ****

use strict;
use warnings;

# set DEBUG in environment to test script
my $debug = $ENV{'DEBUG'};

my @qos_array = (
    'limiter',
    'round-robin',
    'shaper-hfsc',
    'priority-queue',
    'shaper'
);

sub gen_template {
    my ( $inpath, $outpath, $qos_tree ) = @_;

    # Open output path
    print $outpath, "\n" if ($debug);
    opendir my $d, $inpath
      or die "Can't open: $inpath:$!";

    print "cp -R $inpath/* $outpath\n";
    system("cp -R $inpath/* $outpath");

    closedir $d;
}

die "Usage: $0 output_directory\n" if ( $#ARGV < 0 );

my $outdir = $ARGV[0];

sub mkdir_p {
    my $path = shift;

    return 1 if ( mkdir($path) );

    my $pos = rindex( $path, "/" );
    return unless $pos != -1;
    return unless mkdir_p( substr( $path, 0, $pos ) );
    return mkdir($path);
}

# Loop through templates array
foreach my $qos_tree ( @qos_array ) {
    my $inpath  = "templates-skeleton/qos-match-templates";
    my $outpath = "$outdir/traffic-policy/$qos_tree/node.tag";
    ( -d $outpath )
      or mkdir_p($outpath)
      or die "Can't create $outpath:$!";

    gen_template( $inpath, $outpath, $qos_tree );
		 
}
