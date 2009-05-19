# Weighted Random i.e. GRED (Generic Random Early Detect)
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

package Vyatta::Qos::WeightedRandom;
use strict;
use warnings;

require Vyatta::Config;
require Vyatta::Qos::ShaperClass;

my $wred = 'weighted-random-detect';

# Create a new instance based on config information
sub new {
    my ( $that, $config, $name ) = @_;
    my $level = $config->setLevel();
    my $rate  = $config->returnValue("bandwidth");

    my @classes = _getClasses($level);

    _checkClasses( $level, $rate, @classes );

    my $self = {};
    my $class = ref($that) || $that;
    bless $self, $class;
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

# Check constraints on class bandwidth values
sub _checkClasses {
    my $level   = shift;
    my $rate    = shift;
    my $default = shift;

    # if auto, can't check at create must wait for policy to be applied
    $rate = ( $rate eq "auto" ) ? undef : getRate($rate);
    $default->rateCheck( $rate, "$level default" ) if $rate;

    foreach my $class (@_) {
        die "$class->{level} bandwidth not defined\n" unless $class->{_rate};
        $class->rateCheck( $rate, "$level class $class->{id}" ) if $rate;
    }
}

sub commands {
    my ( $self, $dev ) = @_;
    my $rate    = getAutoRate( $self->{_rate}, $dev );
    my $classes = $self->{_classes};
    my $default = shift @$classes;
    my $maxid   = 1;

    $default->rateCheck( $rate, "$self->{_level} default" );
    foreach my $class (@$classes) {
        $class->rateCheck( $rate, "$self->{_level} class $class->{id}" );

        # find largest class id
        if ( defined $class->{id} && $class->{id} > $maxid ) {
            $maxid = $class->{id};
        }
    }

    # fill in id of default
    $default->{id} = ++$maxid;
    unshift @$classes, $default;

    print "qdisc add dev $dev root handle 1: gred";
    print " setup DPs $maxid default $maxid";

    foreach my $class (@$classes) {
        my $classbw = $class->get_rate($rate);
        my $avg     = $class->{_avgpkt};
        my $latency = $class->{_latency};

        my ( $qmin, $qmax, $burst ) = RedParam( $classbw, $latency, $avg );

        print "qdisc chang dev $dev root gred ";
        printf "limit %d min %d max %d avpkt %d", 4 * $qmax, $qmin, $qmax, $avg;
        printf " burst %d probability 0.02 bandwidth %d ecn\n",
          $burst, $classbw / 1000;

        foreach my $match ( $class->matchRules() ) {
            $match->filter( $dev, 1, $class->{_priority} );
            printf " flowid :%x\n", $class->{id};
        }
    }
}

# Walk configuration tree and look for changed nodes
# The configuration system should do this but doesn't do it right
sub isChanged {
    my ( $self, $name ) = @_;
    my $config = new Vyatta::Config;
    my @attributes =
      qw(bandwidth burst latency packet-length priority queue-limit);

    $config->setLevel("qos-policy $wred $name");

    return 'bandwidth' if ( $config->isChanged('bandwidth') );

    foreach my $attr (@attributes) {
	return "default $attr" if ( $config->isChanged("default $attr") );
    }

    my %classNodes = $config->listNodeStatus('class');
    while ( my ( $class, $status ) = each %classNodes ) {
        return "class $class" if ( $status ne 'static' );

        foreach my $attr (@attributes) {
            return "class $class $attr"
              if ( $config->isChanged("class $class $attr") );
        }

        my %matchNodes = $config->listNodeStatus("class $class match");
        while ( my ( $match, $status ) = each %matchNodes ) {
            my $level = "class $class match $match";
            return $level if ( $status ne 'static' );

            foreach my $parm (
                'vif',
                'ether destination',
                'ether source',
                'ether protocol',
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
