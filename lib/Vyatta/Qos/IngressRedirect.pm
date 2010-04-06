# Ingress Redirect
#   Forward all packets to another interface
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
# Portions created by Vyatta are Copyright (C) 2010 Vyatta, Inc.
# All Rights Reserved.
# **** End License ****

package Vyatta::Qos::IngressRedirect;
use strict;
use warnings;

require Vyatta::Config;

sub new {
    my ( $that, $config, $name ) = @_;
    my $self = {};
    my $class = ref($that) || $that;

    bless $self, $class;
    $self->_define($config);

    return $self;
}

# Setup new instance.
sub _define {
    my ( $self, $config, $dev ) = @_;
    # config is at level: interfaces ethernet $dev input-policy redirect
    $self->{_target} = $config->returnValue();
}

sub commands {
    my ( $self, $dev, $parent ) = @_;
    my $target = $self->{_target};

    # Apply filter to ingress qdisc
    # NB: action is egress because we are in ingress (upside down)
    printf "filter add dev %s parent %x: ", $dev, $parent;
    print  " protocol all prio 10 u32"; 
    print  " match u32 0 0 flowid 1:1";
    print  " action mirred egress redirect dev $target\n";
}

1;


