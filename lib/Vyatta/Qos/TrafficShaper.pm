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
use Vyatta::Qos::Util qw/getRate interfaceRate/;

my %fields = (
    _level   => undef,
    _rate    => undef,
    _classes => undef,
);

# Create a new instance based on config information
sub new {
    my ( $that, $config, $name ) = @_;
    my $self = {%fields};
    my $class = ref($that) || $that;

    bless $self, $class;
    $self->_define($config);

    $self->_validate($config);

    return $self;
}

sub _validate {
    my $self = shift;

    if ( $self->{_rate} ne "auto" ) {
        my $classes = $self->{_classes};
        my $default = shift @$classes;
        my $rate    = getRate( $self->{_rate} );

        $default->rateCheck( $rate, "$self->{_level} default" );

        foreach my $class (@$classes) {
            $class->rateCheck( $rate, "$self->{_level} class $class->{id}" );
        }
        unshift @$classes, $default;
    }
}

# Rate can be something like "auto" or "10.2mbit"
sub _getAutoRate {
    my ( $rate, $dev ) = @_;

    if ( $rate eq "auto" ) {
        $rate = interfaceRate($dev);
        if ( !defined $rate ) {
            print STDERR
              "Interface $dev speed cannot be determined (assuming 10mbit)\n";
            $rate = 10000000;
        }
    }
    else {
        $rate = getRate($rate);
    }

    return $rate;
}

# Setup new instance.
# Assumes caller has done $config->setLevel to "traffic-shaper $name"
sub _define {
    my ( $self, $config ) = @_;
    my $level   = $config->setLevel();
    my @classes = ();

    $self->{_rate}  = $config->returnValue("bandwidth");
    $self->{_level} = $level;

    $config->exists("default")
      or die "$level configuration not complete: missing default class\n";

    # make sure no clash of different types of tc filters
    my %matchTypes = ();
    foreach my $class ( $config->listNodes("class") ) {
        foreach my $match ( $config->listNodes("class $class match") ) {
            foreach my $type ( $config->listNodes("class $class match $match") )
            {
                next if ( $type eq 'description' );
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

    $config->setLevel("$level default");
    push @classes, new Vyatta::Qos::ShaperClass($config);
    $config->setLevel($level);

    foreach my $id ( $config->listNodes("class") ) {
        $config->setLevel("$level class $id");
        push @classes, new Vyatta::Qos::ShaperClass( $config, $id );
    }
    $self->{_classes} = \@classes;
}

sub commands {
    my ( $self, $dev ) = @_;
    my $rate    = _getAutoRate( $self->{_rate}, $dev );
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

    $config->setLevel("qos-policy traffic-shaper $name");

    if ( $config->isChanged('bandwidth') ) {
        return 'bandwidth';
    }

    foreach my $attr (
        'bandwidth',   'burst', 'ceiling', 'priority',
        'queue-limit', 'queue-type'
      )
    {
        if ( $config->isChanged("default $attr") ) {
            return "default $attr";
        }
    }

    my %classNodes = $config->listNodeStatus('class');
    while ( my ( $class, $status ) = each %classNodes ) {
        if ( $status ne 'static' ) {
            return "class $class";
        }

        foreach my $attr (
            'bandwidth',   'burst', 'ceiling', 'priority',
            'queue-limit', 'queue-type'
          )
        {
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
                if ( $config->isChanged("$level $parm") ) {
                    return "$level $parm";
                }
            }
        }
    }

    return;    # false
}

1;
