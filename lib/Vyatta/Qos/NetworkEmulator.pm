# This is a wrapper around Network Emulator (netem) queue discipline
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
# Portions created by Vyatta are Copyright (C) 2008 Vyatta, Inc.
# All Rights Reserved.
# **** End License ****

package Vyatta::Qos::NetworkEmulator;

use strict;
use warnings;

require Vyatta::Config;
use Vyatta::Qos::Util;

sub new {
    my ( $that, $config ) = @_;
    my $level = $config->setLevel();
    my $class = ref($that) || $that;
    my $self  = { };

    my $bw = $config->returnValue("bandwidth");
    $self->{_rate} 	 = getRate( $bw ) if ($bw);
    my $delay = $config->returnValue("network-delay");
    $self->{_delay}      = getTime($delay) if ($delay);

    $self->{_burst}      = $config->returnValue("burst");
    $self->{_limit}      = $config->returnValue("queue-limit");
    $self->{_drop}       = $config->returnValue("packet-loss");
    $self->{_corrupt}    = $config->returnValue("packet-corruption");
    $self->{_reorder}    = $config->returnValue("packet-reordering");

    return bless $self, $class;
}

sub commands {
    my ( $self, $dev ) = @_;
    my $rate = $self->{_rate};
    my $limit = $self->{_limit};
    my $delay = $self->{_delay};

    if ($rate) {
        my $burst = $self->{_burst};
        $burst or $burst = "15K";

        printf "qdisc add dev %s root handle 1:0 tbf rate %s burst %s",
          $dev, $rate, $burst;
	if ($limit) {
	    print " limit $limit";
	} elsif ($delay) {
	    print " latency $delay";
	} else {
	    print " latency 50ms";
	}
	printf "\nqdisc add dev %s parent 1:1 handle 10: netem", $dev;
    } else {
        printf "qdisc add dev %s root netem", $dev;
    }
    print " limit $limit" if ($limit);
    print " delay $delay" if ($delay);

    my $drop = $self->{_drop};
    print " drop $drop" if ($drop);

    my $corrupt = $self->{_corrupt};
    print " corrupt $corrupt" if ($corrupt);

    my $reorder = $self->{_reorder};
    print " reorder $reorder" if ($reorder);

    print "\n";
}

1;
