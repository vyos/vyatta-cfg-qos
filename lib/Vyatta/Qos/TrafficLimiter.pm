# Traffic limiter
# This is a rate limiter based on ingress qdisc
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

package Vyatta::Qos::TrafficLimiter;
use strict;
use warnings;

require Vyatta::Config;
require Vyatta::Qos::LimiterClass;

my %fields = (
    _level   => undef,
    _classes => undef,
);

# Create a new instance based on config information
sub new {
    my ( $that, $config, $name ) = @_;
    my $self = {%fields};
    my $class = ref($that) || $that;

    bless $self, $class;
    $self->_define($config);

    return $self;
}

# Setup new instance.
# Assumes caller has done $config->setLevel to "limiter $name"
sub _define {
    my ( $self, $config ) = @_;
    my $level   = $config->setLevel();
    my @classes = ();

    $self->{_level} = $level;

    if ( $config->exists('default') ) {
        $config->setLevel("$level default");
        push @classes, new Vyatta::Qos::LimiterClass( $config, 0 );
    }

    $config->setLevel($level);
    foreach my $id ( $config->listNodes("class") ) {
        $config->setLevel("$level class $id");
        push @classes, new Vyatta::Qos::LimiterClass( $config, $id );
    }
    $self->{_classes} = \@classes;
}

sub commands {
    my ( $self, $dev, $direction ) = @_;
    my $classes = $self->{_classes};
    my $parent;

    die "traffic-policy limiter only applies for incoming traffic\n"
      unless ( $direction eq 'in' );

    $parent = 0xffff;
    printf "qdisc add dev %s handle %x: ingress\n", $dev, $parent;

    # find largest class id (to use for default)
    my $maxid = 0;
    foreach my $class (@$classes) {
	my $id = $class->{id};
	$maxid = $id if ( $id > $maxid );
    }

    foreach my $class (@$classes) {
	my $id = $class->{id};
	my $police = " action police rate " . $class->{rate}
		   . " conform-exceed drop burst " . $class->{burst};

	if ($id == 0) {
	    $id = $maxid + 1;

	    # Null filter for default rule
	    printf "filter add dev %s parent %x: prio %d", $dev, $parent, 255;
	    print  " protocol all basic";
	    printf " %s flowid %x:%x\n", $police, $parent, $id;
	} else {
	    my $prio = $class->{priority};
	    foreach my $match ( $class->matchRules() ) {
		$match->filter( $dev, $parent, $id, $prio, undef, $police );
	    }
	}
    }
}

1;
