# Round Robin
# This is a deficit round robin scheduler
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

package Vyatta::Qos::RoundRobin;
use strict;
use warnings;

require Vyatta::Config;
require Vyatta::Qos::ShaperClass;

# Create a new instance based on config information
sub new {
    my ( $that, $config, $name ) = @_;

    my @classes = _getClasses( $config->setLevel() );
    my $self    = {};
    my $class   = ref($that) || $that;
    bless $self, $class;
    $self->{_classes} = \@classes;

    return $self;
}

sub _getClasses {
    my $level = shift;
    my @classes;
    my $config = new Vyatta::Config;

    $config->setLevel("$level default");
    my $default = new Vyatta::Qos::ShaperClass($config);

    push @classes, $default;
    $default->{id} = 1;

    foreach my $id ( $config->listNodes("class") ) {
        $config->setLevel("$level class $id");
        push @classes, new Vyatta::Qos::ShaperClass( $config, $id );
    }

    return @classes;
}

sub commands {
    my ( $self, $dev ) = @_;
    my $classes = $self->{_classes};
    my $parent  = 1;

    printf "qdisc add dev %s root  handle %x: drr", $dev, $parent;
    print " quantum $self->{_quantum}" if ( $self->{_quantum} );
    print "\n";

    foreach my $class (@$classes) {
        $class->gen_class( $dev, 'drr', $parent );
        $class->gen_leaf( $dev, $parent );
	my $prio = 1;

        foreach my $match ( $class->matchRules() ) {
            $match->filter( $dev, $parent, $class->{id}, $prio++);
        }
    }
}

1;
