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
# Portions created by Vyatta are Copyright (C) 2008 Vyatta, Inc.
# All Rights Reserved.
# **** End License ****

package Vyatta::Qos::Match;
require Vyatta::Config;
use Vyatta::Qos::Util qw(getIfIndex getDsfield getProtocol);

use strict;
use warnings;

sub new {
    my ( $that, $config ) = @_;
    my $self = {};
    my $class = ref($that) || $that;

    bless $self, $class;

    foreach my $proto (qw(ip ipv6 ether)) {
        next unless $config->exists($proto);

        foreach my $t (qw(vif dev)) {
            die "can not match on $proto and $t\n" if $config->exists($t);
        }

        my %fields;

        if ( $proto eq 'ether' ) {
            $fields{protocol} =
              getProtocol( $config->returnValue("ether protocol") );
            $fields{src} = $config->returnValue("ether source");
            $fields{dst} = $config->returnValue("ether destination");
        }
        else {
            $fields{dsfield} =
              getDsfield( $config->returnValue("$proto dscp") );
            $fields{protocol} =
              getProtocol( $config->returnValue("$proto protocol") );
            $fields{src}   = $config->returnValue("$proto source address");
            $fields{dst}   = $config->returnValue("$proto destination address");
            $fields{sport} = $config->returnValue("$proto source port");
            $fields{dport} = $config->returnValue("$proto destination port");
        }

        $self->{$proto} = \%fields;
    }

    $self->{_vif} = $config->returnValue("vif");
    $self->{_dev} = getIfIndex( $config->returnValue("interface") );

    return $self;
}

sub filter {
    my ( $self, $dev, $parent, $prio, $dsmark ) = @_;

    # empty match
    return unless %{$self};

    # Special case for when dsmarking is used with ds matching
    # original dscp is saved in tc_index
    if ($dsmark) {
        foreach my $ipver (qw(ip ipv6)) {
            my $ip = $self->{$ipver};
            next unless $ip && $$ip{dsfield};

            printf "filter add dev %s parent %x: protocol $ipver prio 1",
              $dev, $parent;
            printf " handle %d tcindex", $$ip{dsfield};
        }
        return;
    }

    foreach my $proto (qw(ip ipv6 ether)) {
        my $p = $self->{$proto};
        next unless $p;

        printf "filter add dev %s parent %x:", $dev, $parent;
	printf " prio %d", $prio  if ($prio);

	if ($proto ne 'ether') {
	    print " protocol $proto u32";
	    print " match $proto dsfield $$p{dsfield} 0xff"   if $$p{dsfield};
	    print " match $proto protocol $$p{protocol} 0xff" if $$p{protocol};
	} else {
	    my $type = $$p{protocol};
	    $type = 'all' unless $type;

	    print " protocol $type u32";
	}

	# workaround inconsistent usage in tc u32 match
	$proto = 'ip6' if ($proto eq 'ipv6');

        print " match $proto src $$p{src}"                if $$p{src};
        print " match $proto sport $$p{sport} 0xffff"     if $$p{sport};
        print " match $proto dst $$p{dst}"                if $$p{dst};
        print " match $proto dport $$p{dport} 0xffff"     if $$p{dport};
    }

    my $indev = $self->{indev};
    my $vif   = $self->{vif};
    if ( $vif || $indev ) {
        printf "filter add dev %s parent %x: prio %d", $dev, $parent, $prio;
        print " protocol all basic";
        print " match meta\(rt_iif eq $indev\)"        if $indev;
        print " match meta\(vlan mask 0xfff eq $vif\)" if $vif;
    }
}
