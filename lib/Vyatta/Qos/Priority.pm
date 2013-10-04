# Priority Queue
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

package Vyatta::Qos::Priority;
use strict;
use warnings;

require Vyatta::Config;
require Vyatta::Qos::ShaperClass;
use POSIX;

# Kernel limits on quantum (bytes)
use constant {
   MAXQUANTUM  => 200000,
   MINQUANTUM  => 1000,
};


# Create a new instance based on config information
sub new {
    my ( $that, $config, $name ) = @_;
    my $level   = $config->setLevel();
    my @classes = _getClasses($level);

    my $self = {};
    my $class = ref($that) || $that;
    bless $self, $class;

    $self->{_level}   = $level;
    $self->{_classes} = \@classes;
    return $self;
}

sub _getClasses {
    my $level = shift;
    my @classes;
    my $config = new Vyatta::Config;

    $config->setLevel($level);
    $config->exists("default")
      or die "$level configuration not complete: missing default class\n";

    $config->setLevel("$level default");
    push @classes, new Vyatta::Qos::ShaperClass($config);
    $config->setLevel($level);

    foreach my $id ( $config->listNodes("class") ) {
        $config->setLevel("$level class $id");
        push @classes, new Vyatta::Qos::ShaperClass( $config, $id );
    }

    return @classes;
}

# Note: priority does not have internal classes, only sub-qdisc's
#
# Although Linux supports mapping TOS and priority to bands, this
# is not used here. Instead we apply filters to traffic and statically
# assign bands.
sub commands {
    my ( $self, $dev ) = @_;
    my $classes = $self->{_classes};
    my $default = shift @$classes;
    my $maxid   = 1;
    my $bands = 2;

    foreach my $class (@$classes) {
	my $level = "$self->{_level} class $class->{id}";
	$class->valid_leaf( $level );

        # find largest class id
	$maxid = $class->{id}
        if ( defined $class->{id} && $class->{id} > $maxid );
    }

    # fill in id of default
    $default->{id} = ++$maxid;
    $bands = $default->{id};
    unshift @$classes, $default;

    my $parent = 1;
    my $root   = "root";

    my $def_prio = $bands - 1;
    # Since we use filters to set priority 
    printf "qdisc add dev %s %s handle %x: prio bands %d priomap %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
	$dev, $root, $parent, $bands, 
        $def_prio, $def_prio, $def_prio, $def_prio, $def_prio, $def_prio, $def_prio,
        $def_prio, $def_prio, $def_prio, $def_prio, $def_prio, $def_prio, $def_prio, 
        $def_prio, $def_prio, $def_prio;

    # prio is not really classful!
    my $prio = 1;
    foreach my $class (@$classes) {
	$class->gen_leaf( $dev, $parent );
        foreach my $match ( $class->matchRules() ) {
            $match->filter( $dev, $parent, $class->{id}, $prio++ );
        }
    }
}

1;
