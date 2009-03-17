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

my %fields = (
    _rate    => undef,
    _burst   => undef,
    _limit   => undef,
    _delay   => undef,
    _drop    => undef,
    _corrupt => undef,
    _reorder => undef,
);

sub new {
    my ( $that, $config ) = @_;
    my $level = $config->setLevel();
    my $class = ref($that) || $that;
    my $self  = {%fields};

    $self->{_rate} = getRate( $config->returnValue("bandwidth") );
    $self->{_burst}      = $config->returnValue("burst");
    $self->{_limit}       = $config->returnValue("queue-limit");
    $self->{_delay}       = getTime($config->returnValue("network-delay"));
    $self->{_drop}        = $config->returnValue("packet-loss");
    $self->{_corrupt}     = $config->returnValue("packet-corruption");
    $self->{_reorder}     = $config->returnValue("packet-reordering");


    return bless $self, $class;
}

sub commands {
    my ( $self, $dev ) = @_;
    my $rate = $self->{_rate};

    if ($rate) {
        my $burst = $self->{_burst};
        $burst or $burst = "15K";

        printf "qdisc add dev %s root handle 1:0 tbf rate %s burst %s\n",
          $dev, $rate, $burst;
        printf "qdisc add dev %s parent 1:1 handle 10: netem";
    }
    else {
        printf "qdisc add dev %s root netem";
    }

    my $delay = $self->{_delay};
    print " delay $delay" if ($delay);

    my $limit = $self->{_limit};
    print " limit $limit" if ($limit);

    my $drop = $self->{_drop};
    print " drop $drop" if ($drop);

    my $corrupt = $self->{_corrupt};
    print " corrupt $corrupt" if ($corrupt);

    my $reorder = $self->{_reorder};
    print " reorder $reorder" if ($reorder);

    print "\n";
}

sub isChanged {
    my ( $self, $name ) = @_;
    my $config = new Vyatta::Config;

    $config->setLevel("qos-policy network-emulator $name");
    foreach my $attr ( "bandwidth", "burst", "queue-limit", "network-delay", 
		       "packet-loss", "packet-corruption", "packet-reordering", ) {
        return $attr if ( $config->isChanged($attr) );
    }
    return;
}

1;
