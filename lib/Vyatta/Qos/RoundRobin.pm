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

    $config->setLevel($level);
    my $default;
    if ( $config->exists("default") ) {
        $config->setLevel("$level default");
        $default = new Vyatta::Qos::ShaperClass($config);
        $config->setLevel($level);
    }
    else {
        $default = new Vyatta::Qos::ShaperClass;
    }
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

    printf "qdisc add dev %s s handle %x: drr", $dev, 'root', $parent;
    my $quantum = $self->{_quantum};
    print " quantum $quantum" if ($quantum);
    print "\n";

    foreach my $class (@$classes) {
        $class->gen_leaf( $dev, $parent );
        foreach my $match ( $class->matchRules() ) {
            $match->filter( $dev, $parent, 1 );
            printf " classid %x:%x\n", $parent, $class->{id};
        }
    }
}

# Walk configuration tree and look for changed nodes
# The configuration system should do this but doesn't do it right
sub isChanged {
    my ( $self, $name ) = @_;
    my $config = new Vyatta::Config;

    $config->setLevel("qos-policy round-robin $name");

    return 'quantum' if ( $config->isChanged('quantum') );

    foreach my $attr (qw(queue-limit queue-type)) {
        return "default $attr" if ( $config->isChanged("default $attr") );
    }

    my %classNodes = $config->listNodeStatus('class');
    while ( my ( $class, $status ) = each %classNodes ) {
        return "class $class" if ( $status ne 'static' );

        foreach my $attr (qw(queue-limit queue-type)) {
            return "class $class $attr"
              if ( $config->isChanged("class $class $attr") );
        }

        my %matchNodes = $config->listNodeStatus("class $class match");
        while ( my ( $match, $status ) = each %matchNodes ) {
            my $level = "class $class match $match";
            if ( $status ne 'static' ) {
                return $level;
            }

            foreach my $parm (
                (
                    'vif',
                    'interface',
                    'ip protocol',
                    'ip source address',
                    'ip destination address',
                    'ip source port',
                    'ip destination port'
                )
              )
            {
                return "$level $parm"
                  if ( $config->isChanged("$level $parm") );
            }
        }
    }

    return;    # false
}

1;
