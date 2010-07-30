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
require Vyatta::Qos::Match;

# Create a new instance based on config information
sub new {
    my ( $that, $config, $name ) = @_;
    my @classes = _getClasses( $config->setLevel() );

    _checkClasses( @classes );

    my $self    = {};
    my $class   = ref($that) || $that;
    bless $self, $class;
    $self->{_classes} = \@classes;

    return $self;
}

# Check constraints on sub queues
sub _checkClasses {
    my $level   = shift;

    foreach my $class (@_) {
	my $level = $class->{level};
	my $qtype = $class->{_qdisc};
	my $qlimit = $class->{_limit};

	if (defined($qtype) && $qtype eq 'random-detect' 
	    && defined($qlimit) && $qlimit >= 128) {
	    print STDERR "Configuration error in: $level\n";
	    die "queue limit must be between 1 and 127 for random-detect\n";
	}
    }
}

sub _getClasses {
    my $level = shift;
    my $config = new Vyatta::Config;
    my @classes;

    $config->setLevel($level);
    foreach my $id ( $config->listNodes("class") ) {
        $config->setLevel("$level class $id");
        push @classes, new Vyatta::Qos::ShaperClass( $config, $id );
    }

    $config->setLevel("$level default");
    my $default = new Vyatta::Qos::ShaperClass($config, 4096);

    # Workaround for lack of default class in drr qdisc
    $default->{_match} = [ new Vyatta::Qos::Match() ];
    push @classes, $default;

    return @classes;
}

sub commands {
    my ( $self, $dev ) = @_;
    my $classes = $self->{_classes};
    my $parent  = 1;

    printf "qdisc add dev %s root  handle %x: drr\n", $dev, $parent;

    foreach my $class (sort { $a->{id} <=> $b->{id} } @$classes) {
        $class->gen_class( $dev, 'drr', $parent );
        $class->gen_leaf( $dev, $parent );

        foreach my $match ( $class->matchRules() ) {
            $match->filter( $dev, $parent, $class->{id}, $class->{id} );
        }
    }
}

1;
