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
# Assumes caller has done $config->setLevel to "traffic-limiter $name"
sub _define {
    my ( $self, $config ) = @_;
    my $level   = $config->setLevel();
    my @classes = ();

    $self->{_level} = $level;

    # make sure no clash of different types of tc filters
    my %matchTypes = ();
    foreach my $class ( $config->listNodes("class") ) {
        foreach my $match ( $config->listNodes("class $class match") ) {
            foreach my $type ( $config->listNodes("class $class match $match") ) {
		next if ($type eq 'description');
                $matchTypes{$type} = "$class match $match";
            }
        }
    }

    if ( scalar keys %matchTypes > 1 && $matchTypes{ip} ) {
        print "Match type conflict:\n";
        while ( my ( $type, $usage ) = each(%matchTypes) ) {
            print "   class $usage $type\n";
        }
        die "$level can not match on both ip and other types\n";
    }

    foreach my $id ( $config->listNodes("class") ) {
        $config->setLevel("$level class $id");
        push @classes, new Vyatta::Qos::LimiterClass( $config, $id );
    }
    $self->{_classes} = \@classes;
}

sub commands {
    my ( $self, $out, $dev ) = @_;
    my $classes = $self->{_classes};
    my $parent  = 0xffff;

    printf {$out} "qdisc add dev %s handle %x: ingress\n", $dev, $parent;
    foreach my $class (@$classes) {
        foreach my $match ( $class->matchRules() ) {
	    $match->filter( $out, $dev, $parent, $class->{priority} );
	    printf {$out} " police rate %s burst %s drop flowid :%x\n", 
	        $class->{rate}, $class->{burst}, $class->{id};
        }
    }
}

# Walk configuration tree and look for changed nodes
# The configuration system should do this but doesn't do it right
sub isChanged {
    my ( $self, $name ) = @_;
    my $config = new Vyatta::Config;

    $config->setLevel("qos-policy traffic-limiter $name");
    my %classNodes = $config->listNodeStatus('class');
    while ( my ( $class, $status ) = each %classNodes ) {
        if ( $status ne 'static' ) {
            return "class $class";
        }

        foreach my $attr ( 'bandwidth', 'burst', 'priority' ) {
            if ( $config->isChanged("class $class $attr") ) {
                return "class $class $attr";
            }
        }

        my %matchNodes = $config->listNodeStatus("class $class match");
        while ( my ( $match, $status ) = each %matchNodes ) {
            my $level = "class $class match $match";
            if ( $status ne 'static' ) {
                return $level;
            }

            foreach my $parm (
                'vif',
                'interface',
                'ip dscp',
                'ip protocol',
                'ip source address',
                'ip destination address',
                'ip source port',
                'ip destination port'
              )
            {
		return "$level $parm" if ( $config->isChanged("$level $parm") );
            }
        }
    }

    return;    # false
}

1;
