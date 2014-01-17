# Traffic limiter sub-class

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

package Vyatta::Qos::LimiterClass;
use strict;
use warnings;

require Vyatta::Config;
use Vyatta::Qos::Match;
use Vyatta::Qos::Util qw/getRate/;

my %fields = (
    id       => undef,
    priority => undef,
    burst    => undef,
    rate     => undef,
    _match   => undef,
);

sub new {
    my ( $that, $config, $id ) = @_;
    my $class = ref($that) || $that;
    my $self = {%fields};

    $self->{id} = $id;

    bless $self, $class;
    $self->_define($config);

    return $self;
}

sub _define {
    my ( $self, $config ) = @_;
    my $level   = $config->setLevel();
    my @matches = ();
    my $rate    = $config->returnValue("bandwidth");

    die "bandwidth must be defined for $level\n" unless $rate;
    $self->{rate} = getRate($rate);

    $self->{burst} = $config->returnValue("burst");
    defined $self->{burst} or die "burst must be defined for $level\n";

    $self->{priority} = $config->returnValue("priority");

    foreach my $match ( $config->listNodes("match") ) {
        $config->setLevel("$level match $match");
        my $match = new Vyatta::Qos::Match($config);
        if (defined($match)) {
            push @matches,  $match;
        }
    }
    $self->{_match} = \@matches;
}

sub matchRules {
    my ($self) = @_;
    my $matches = $self->{_match};
    return @$matches;
}

1;
