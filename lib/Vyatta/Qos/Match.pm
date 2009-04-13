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
    my $self = { };
    my $class = ref($that) || $that;

    bless $self, $class;

    foreach my $ip (qw(ip ipv6)) {
	next unless $config->exists($ip);

	foreach my $t (qw(vif dev)) {
	    die "can not match on $ip and $t\n" if $config->exists($t);
	}

	# TODO make this data driven?
	my %fields;
	$fields{dsfield} = getDsfield( $config->returnValue("$ip dscp"));
	$fields{protocol} = getProtocol($config->returnValue("$ip protocol"));
	$fields{src} = $config->returnValue("$ip source address");
	$fields{dst} = $config->returnValue("$ip destination address");
	$fields{sport} = $config->returnValue("$ip source port");
	$fields{dport} = $config->returnValue("$ip destination port");
	$self->{$ip} = \%fields;
    }

    $self->{_vif} = $config->returnValue("vif");
    $self->{_dev} = getIfIndex($config->returnValue("interface"));

    return $self;
}

sub filter {
    my ( $self, $dev, $parent, $prio, $dsmark ) = @_;
    
    # empty match
    return unless %{ $self };

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

    foreach my $ipver (qw(ip ipv6)) {
	my $ip = $self->{$ipver};
	next unless $ip;

	printf "filter add dev %s parent %x: prio %d", $dev, $parent, $prio;
	print " protocol $ipver u32";
	print " match $ipver dsfield $$ip{dsfield} 0xff"
	    if defined $$ip{dsfield};
	print " match $ipver protocol $$ip{protocol} 0xff"
		if defined $$ip{protocol};
	print " match $ipver src $$ip{src}"
	    if defined $$ip{src};
	print " match $ipver sport $$ip{sport} 0xffff"
	    if defined $$ip{sport};
	print " match $ipver dst $$ip{dst}"
		if defined $$ip{dst};
	print " match $ipver dport $$ip{dport} 0xffff"
		if defined $$ip{dport};
    }

    my $indev = $self->{indev};
    my $vif = $self->{vif};
    if ($vif || $indev) {
	printf "filter add dev %s parent %x: prio %d", $dev, $parent, $prio;
	print " protocol all basic";
	print " match meta\(rt_iif eq $indev\)"		if $indev;
	print " match meta\(vlan mask 0xfff eq $vif\)" if $vif;
    }
}
