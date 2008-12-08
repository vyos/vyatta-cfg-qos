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

my %fields = (
	_dev      => undef,
	_vif      => undef,
	_ip	  => undef,
);

sub new {
    my ( $that, $config ) = @_;
    my $self = {%fields};
    my $class = ref($that) || $that;

    bless $self, $class;
    $self->_define($config);

    return $self;
}

sub _define {
    my ( $self, $config ) = @_;
    my $level = $config->setLevel();

    $self->{_vif} = $config->returnValue("vif");
    $self->{_dev} = getIfIndex($config->returnValue("interface"));

    if ($config->exists("ip")) {
	my %ip;

	$ip{dsfield} = getDsfield( $config->returnValue("ip dscp"));
	$ip{protocol} = getProtocol($config->returnValue("ip protocol"));
	$ip{src} = $config->returnValue("ip source address");
	$ip{dst} = $config->returnValue("ip destination address");
	$ip{sport} = $config->returnValue("ip source port");
	$ip{dport} = $config->returnValue("ip destination port");
	$self->{_ip} = \%ip;
    }
}

sub filter {
    my ( $self, $out, $dev, $parent, $prio, $dsmark ) = @_;
    my $ip = $self->{_ip};
    my $indev = $self->{_dev};
    my $vif = $self->{_vif};

    # Catch empty match
    if (! (defined $ip || defined $indev || defined $vif)) {
	return;
    }

    # Special case for when dsmarking is used with ds matching
    # original dscp is saved in tc_index
    if (defined $dsmark && defined $ip && defined $$ip{dsfield}) {
	printf {$out} "filter add dev %s parent %x: protocol ip prio 1",
		$dev, $parent;
	printf ${out} " handle %d tcindex", $$ip{dsfield};
	return;
    }

    printf {$out} "filter add dev %s parent %x: prio %d", $dev, $parent, $prio;
    if (defined $ip) {
	print {$out} " protocol ip u32";
	print {$out} " match ip dsfield $$ip{dsfield} 0xff"
	    if defined $$ip{dsfield};
	print {$out} " match ip protocol $$ip{protocol} 0xff"
	    if defined $$ip{protocol};
	print {$out} " match ip src $$ip{src}"
	    if defined $$ip{src};
	print {$out} " match ip sport $$ip{sport} 0xffff"
	    if defined $$ip{sport};
	print {$out} " match ip dst $$ip{dst}"
	    if defined $$ip{dst};
	print {$out} " match ip dport $$ip{dport} 0xffff"
	    if defined $$ip{dport};
    } else {
	print {$out} " protocol all basic";
	print {$out} " match meta\(rt_iif eq $indev\)"
	    if (defined $indev);
	print {$out} " match meta\(vlan mask 0xfff eq $vif\)"
	    if (defined $vif);
    }
}
