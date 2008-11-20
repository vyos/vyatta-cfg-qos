# This is a wrapper around Stochastic Fair Queue(SFQ) queue discipline
# Since SFQ is a hard to explain, use the name fair-queue since SFQ
# is most similar to Weighted Fair Queue (WFQ) on Cisco IOS.
#
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

package Vyatta::Qos::FairQueue;

use strict;
use warnings;

require VyattaConfig;

# Fair Queue
# Uses SFQ which is similar to (but not same as) WFQ

my %fields = (
    _perturb => undef,
    _limit   => undef,
);

sub new {
    my ( $that, $config ) = @_;
    my $class = ref($that) || $that;
    my $self = {%fields};

    $self->{_perturb} = $config->returnValue('hash-interval');
    $self->{_limit}   = $config->returnValue('queue-limit');
    return bless $self, $class;
}

sub commands {
    my ( $self, $out, $dev ) = @_;
    
    print {$out} "qdisc add dev $dev root sfq";
    print {$out} " perturb $self->{_perturb}" if ( defined $self->{_perturb} );
    print {$out} " limit $self->{_limit}"     if ( defined $self->{_limit} );
    print "\n";
}

sub isChanged {
    my ( $self, $name ) = @_;
    my $config = new VyattaConfig;

    $config->setLevel("qos-policy fair-queue $name");
    foreach my $attr ('hash-interval', 'queue-limit') {
	if ($config->isChanged($attr)) {
	    return $attr
	}
    }
    return undef; # false
}

1;
