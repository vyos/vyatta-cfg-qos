# Traffic shaper
# This is a extended form of Hierarchal Token Bucket with
# more admin friendly features. Similar in spirt to other shaper scripts
# such as wondershaper.
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

package Vyatta::Qos::TrafficShaper;
use strict;
use warnings;

require Vyatta::Config;
require Vyatta::Qos::ShaperClass;
use Vyatta::Qos::Util qw/getRate getAutoRate/;

# Create a new instance based on config information
sub new {
    my ( $that, $config, $name ) = @_;
    my $rate    = $config->returnValue("bandwidth");
    my $level   = $config->setLevel();
    my @classes = _getClasses($level);

    _checkClasses( $level, $rate, @classes );

    my $self = {};
    my $class = ref($that) || $that;
    bless $self, $class;

    $self->{_rate}    = $rate;
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

# Check constraints on class bandwidth values
sub _checkClasses {
    my $level = shift;
    my $rate = shift;
    my $default = shift;
    
    # if auto, can't check at create must wait for policy to be applied
    $rate = ( $rate eq "auto") ? undef : getRate($rate);
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
    my %dsmark  = ();
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

    # Check if we need dsmrk
    my $usedsmark;
    foreach my $class (@$classes) {
        if ( defined $class->{dsmark} ) {
            $usedsmark = 1;
            last;
        }
    }

    my $parent = 1;
    my $root   = "root";

    # if we need to change dsfield values, then put dsmark in front
    if ($usedsmark) {

        # dsmark max index must be power of 2
        my $indices = $maxid + 1;
        while ( ( $indices & ( $indices - 1 ) ) != 0 ) {
            ++$indices;
        }

        print "qdisc add dev $dev handle 1:0 root dsmark"
          . " indices $indices default_index $default->{id} set_tc_index\n";

        foreach my $class (@$classes) {
            $class->dsmarkClass( 1, $dev );
            foreach my $match ( $class->matchRules() ) {
                $match->filter( $dev, 1, 1 );
                printf " classid %x:%x\n", $parent, $class->{id};
            }
        }

        $parent = $indices + 1;
        $root   = "parent 1:1";
    }

    printf "qdisc add dev %s %s handle %x: htb default %x\n",
      $dev, $root, $parent, $default->{id};
    printf "class add dev %s parent %x: classid %x:1 htb rate %s\n",
      $dev, $parent, $parent, $rate;

    foreach my $class (@$classes) {
        $class->gen_class( $dev, 'htb', $parent, $rate );
        $class->gen_leaf( $dev, $parent, $rate );

        foreach my $match ( $class->matchRules() ) {
            $match->filter( $dev, $parent, 1, $class->{dsmark} );
            printf " classid %x:%x\n", $parent, $class->{id};
        }
    }
}

# Walk configuration tree and look for changed nodes
# The configuration system should do this but doesn't do it right
sub isChanged {
    my ( $self, $name ) = @_;
    my $config = new Vyatta::Config;
    my @attributes = qw(bandwidth burst ceiling priority queue-limit queue-type);

    $config->setLevel("qos-policy traffic-shaper $name");

    if ( $config->isChanged('bandwidth') ) {
        return 'bandwidth';
    }

    foreach my $attr (@attributes)  {
        if ( $config->isChanged("default $attr") ) {
            return "default $attr";
        }
    }

    my %classNodes = $config->listNodeStatus('class');
    while ( my ( $class, $status ) = each %classNodes ) {
        if ( $status ne 'static' ) {
            return "class $class";
        }

        foreach my $attr (@attributes) {
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
                if ( $config->isChanged("$level $parm") ) {
                    return "$level $parm";
                }
            }
        }
    }

    return;    # false
}

1;
