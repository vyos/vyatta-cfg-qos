# Common op/conf mode QoS functions
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

package Vyatta::Qos::Shared;
use strict;
use warnings;
use lib '/opt/vyatta/share/perl5';
use Vyatta::Config;
use Vyatta::Interface;
use Vyatta::Misc;
use vars qw(%policies);

our @EXPORT =
   qw(find_policy interfaces_using get_policy_names list_policy %policies);
use base qw(Exporter);

our %policies = ( 
    'out' => {
        'shaper'           => 'TrafficShaper',
        'fair-queue'       => 'FairQueue',
        'rate-control'     => 'RateLimiter',
        'drop-tail'        => 'DropTail',
        'network-emulator' => 'NetworkEmulator',
        'round-robin'      => 'RoundRobin',
        'priority-queue'   => 'Priority',
        'random-detect'    => 'RandomDetect',
    },  
    'in' => {
        'limiter' => 'TrafficLimiter',
    }   
);

# find policy for name - also check for duplicates
# find_policy('limited')
sub find_policy {
    my $name   = shift;
    my $config = new Vyatta::Config;

    # op or conf mode?
    my $mode = $config->inSession();
    my $exists = ($mode ? 'exists': 'isEffective');
    my $listNodes = ($mode ? 'listNodes' : 'listEffectiveNodes');

    $config->setLevel('traffic-policy');
    my @policy = grep { $config->$exists("$_ $name") } $config->$listNodes();

    die "Policy name \"$name\" conflict, used by: ", join( ' ', @policy ), "\n"
        if ( $#policy > 0 );

   return $policy[0];
}

# return array of references to (name, direction, policy)
sub interfaces_using {
    my $policy = shift;
    my $config = new Vyatta::Config;
    my @inuse  = ();

    # op or conf mode?
    my $mode = $config->inSession();
    my $listNodes = ($mode ? 'listNodes' : 'listEffectiveNodes');
    my $returnValue = ($mode ? 'returnValue' : 'returnEffectiveValue');

    foreach my $name ( getInterfaces() ) {
        my $intf = new Vyatta::Interface($name);
        next unless $intf;
        my $level = $intf->path() . ' traffic-policy';
        $config->setLevel($level);

        foreach my $direction ($config->$listNodes()) {
            my $cur = $config->$returnValue($direction);
            next unless $cur;

            # these are arguments to update_interface()
            push @inuse, [ $name, $direction, $policy ]
                if ($cur eq $policy);
        }
    }
    return @inuse;
}

# return array of defined qos policy names
sub get_policy_names {
    my $config = new Vyatta::Config;
    my @names = ();
    my @args = @_;

    # op or conf mode?
    my $mode = $config->inSession();
    my $listNodes = ($mode ? 'listNodes' : 'listEffectiveNodes');

    $config->setLevel('traffic-policy');

    foreach my $direction ( @args ) { 
        my @qos = grep { $policies{$direction}{$_} } $config->$listNodes();
        foreach my $type (@qos) {
            my @n = $config->$listNodes($type);
            push @names, @n; 
        }   
    }
    return @names;
}

# list all policy names
sub list_policy {
    my @args = @_;
    my @names = get_policy_names(@args);
    print join( ' ', @names ), "\n";
}

1;
