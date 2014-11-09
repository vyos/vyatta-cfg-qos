# This is a wrapper around fq_codel queue discipline
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

package Vyatta::Qos::FairQueueCodel;

use strict;
use warnings;

require Vyatta::Config;

# Fair Queue Codel
# Uses fq_codel

my %fields = (
    _limit    => undef,
    _flows    => undef,
    _target   => undef,
    _interval => undef,
    _quantum  => undef,
);

sub new {
    my ( $that, $config ) = @_;
    my $class = ref($that) || $that;
    my $self = {%fields};

    $self->{_limit}    = $config->returnValue('queue-limit');
    $self->{_flows}    = $config->returnValue('flows');
    $self->{_target}   = $config->returnValue('target');
    $self->{_interval} = $config->returnValue('interval');
    $self->{_quantum}  = $config->returnValue('quantum');
    return bless $self, $class;
}

sub commands {
    my ( $self, $dev ) = @_;

    print "qdisc add dev $dev root fq_codel";
    print " limit    $self->{_limit}"    if ( $self->{_limit} );
    print " flows    $self->{_flows}"    if ( $self->{_flows} );
    print " target   $self->{_target}"   if ( $self->{_target} );
    print " interval $self->{_interval}" if ( $self->{_interval} );
    print " quantum  $self->{_quantum}"  if ( $self->{_quantum} );
    print " noecn\n";
}

1;
