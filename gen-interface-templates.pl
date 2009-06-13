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

# Mapping from configuration level to ifname used AT THAT LEVEL
my %interface_hash = (
    'loopback/node.tag'                             => '$VAR(@)',
    'ethernet/node.tag'                             => '$VAR(@)',
    'ethernet/node.tag/pppoe/node.tag'              => 'pppoe$VAR(@)',
    'ethernet/node.tag/vif/node.tag'                => '$VAR(../@).$VAR(@)',
    'ethernet/node.tag/vif/node.tag/pppoe/node.tag' => 'pppoe$VAR(@)',
    'wireless/node.tag'                             => '$VAR(@)',
    'bonding/node.tag'                              => '$VAR(@)',
    'bonding/node.tag/vif/node.tag'                 => '$VAR(../@).$VAR(@)',
    'pseudo-ethernet/node.tag'                      => '$VAR(@)',
#   'pseudo-ethernet/node.tag/vif/node.tag'         => '$VAR(../@).$VAR(@)',

    'tunnel/node.tag'                               => '$VAR(@)',
    'bridge/node.tag'                               => '$VAR(@)',
    'openvpn/node.tag'                              => '$VAR(@)',
    'wirelessmodem/node.tag'                        => '$VAR(@)',
    'multilink/node.tag/vif/node.tag'               => '$VAR(../@)',

    'adsl/node.tag/pvc/node.tag/bridged-ethernet' => '$VAR(../../@)',
    'adsl/node.tag/pvc/node.tag/classical-ipoa'   => '$VAR(../../@)',
    'adsl/node.tag/pvc/node.tag/pppoa/node.tag'   => '$VAR(../../@)',
    'adsl/node.tag/pvc/node.tag/pppoe/node.tag'   => '$VAR(../../@)',

    'serial/node.tag/cisco-hdlc/vif/node.tag'  => '$VAR(../../@).$VAR(@)',
    'serial/node.tag/frame-relay/vif/node.tag' => '$VAR(../../@).$VAR(@)',
    'serial/node.tag/ppp/vif/node.tag'         => '$VAR(../../@).$VAR(@)',
);

sub gen_template {
    my ( $outpath, $ifname ) = @_;
    $ifname =~ s#@\)#..\/..\/@\)#g;

    print $outpath, "\n" if ($debug);
    $outpath .= "/qos-policy";
    mkdir $outpath
      or die "Can't mkdir $outpath: $!";

    open my $node, '>', "$outpath/node.def"
      or die "Can't open $outpath/node.def: $!";
    print $node "help: Set Quality of Service (QOS) policy for interface\n";
    close $node
      or die "Can't write $outpath/node.def: $!";

    foreach my $dir qw(in out) {
        my $path = "$outpath/$dir";

        mkdir $path
          or die "Can't create directory: $path: $!";
        open my $node, '>', "$path/node.def"
          or die "Can't open $path/node.def: $!";
        select $node;
        print <<EOF;
type: txt
help: Set ${dir}bound QOS policy for interface
allowed: /opt/vyatta/sbin/vyatta-qos.pl --list-policy $dir
update: /opt/vyatta/sbin/vyatta-qos.pl --update-interface $ifname $dir \$VAR(@)
delete: /opt/vyatta/sbin/vyatta-qos.pl --delete-interface $ifname $dir
EOF
        select STDOUT;
        close $node
          or die "Can't write $path/node.def: $!";
    }
}

sub mkdir_p {
    my $path = shift;

    return 1 if ( mkdir($path) );

    my $pos = rindex( $path, "/" );
    return unless $pos != -1;
    return unless mkdir_p( substr( $path, 0, $pos ) );
    return mkdir($path);
}

die "Usage: $0 output_directory\n" if ( $#ARGV < 0 );

my $outdir = $ARGV[0];

foreach my $if_tree ( keys %interface_hash ) {
    my $outpath = "$outdir/interfaces/$if_tree";
    ( -d $outpath )
      or mkdir_p($outpath)
      or die "Can't create $outpath:$!";

    gen_template( $outpath, $interface_hash{$if_tree} );
}
