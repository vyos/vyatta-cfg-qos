# This is a wrapper around FIFO queue discipline
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

package VyattaQosDropTail;

use strict;
require VyattaConfig;
use VyattaQosUtil;

my %fields = (
    _limit	=> undef,
);

sub new {
    my ( $that, $config ) = @_;
    my $level = $config->setLevel();
    my $class = ref($that) || $that;
    my $self = {%fields};

    $self->{_limit}     = $config->returnValue("queue-limit");

    return bless $self, $class;
}

sub commands {
    my ( $self, $out, $dev ) = @_;
    my $limit = $self->{_limit};
    my $cmd = "qdisc add dev $dev root pfifo";

    $cmd .= " limit $limit" if defined $limit;
    printf {$out} "%s\n", $cmd;
}

sub isChanged {
    my ($self, $name) = @_;
    my $config = new VyattaConfig;

    $config->setLevel("qos-policy drop-tail $name");
    return $config->isChanged('queue-limit');
}

1;
