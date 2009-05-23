# Random Detect
#
# This Qos module uses DSMARK and GRED to provide a policy
# similar to Cisco Weighted Random Detect.
#
# See Almesberger, Werner; Hadi Salim, Jamal; Kuznetsov, Alexey
# "Differentiated Services on Linux"
# http://www.almesberger.net/cv/papers/18270721.pdf
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

package Vyatta::Qos::RandomDetect;
use strict;
use warnings;

require Vyatta::Config;
use Vyatta::Qos::Util qw/getRate getAutoRate getTime/;

# default values for different precedence levels
my @default_fields = (
    { 'min-threshold' => 9,  'max-threshold' => 18, 'mark-probability' => 1/2 },
    { 'min-threshold' => 10, 'max-threshold' => 18, 'mark-probability' => 5/9 },
    { 'min-threshold' => 11, 'max-threshold' => 18, 'mark-probability' => .1 },
    { 'min-threshold' => 12, 'max-threshold' => 18, 'mark-probability' => 2/3 },
    { 'min-threshold' => 13, 'max-threshold' => 18, 'mark-probability' => .1 },
    { 'min-threshold' => 14, 'max-threshold' => 18, 'mark-probability' => 7/9 },
    { 'min-threshold' => 15, 'max-threshold' => 18, 'mark-probability' => 5/6 },
    { 'min-threshold' => 16, 'max-threshold' => 18, 'mark-probability' => 8/9 },
);

# Create a new instance based on config information
sub new {
    my ( $that, $config, $name ) = @_;
    my $level = $config->setLevel();

    my $rate = $config->returnValue("bandwidth");
    die "$level bandwidth configuration missing" unless $rate;
    my @precedence = getPrecedence( $level );

    my $self = {};
    my $class = ref($that) || $that;
    bless $self, $class;

    $self->{_rate}       = $rate;
    $self->{_precedence} = \@precedence;

    return $self;
}

sub getPrecedence {
    my ( $level ) = @_;
    my $config = new Vyatta::Config;
    my @precedence;

    for ( my $i = 0 ; $i <= 7 ; $i++ ) {
	my $defaults = $default_fields[$i];
	my %param;
	
	$config->setLevel("$level precedence $i");
	foreach my $field (keys %$defaults) {
	    my $val = $config->returnValue($field);

            if ( !defined $val ) {
		$param{$field} = $defaults->{$field};
            } elsif ( $field eq 'mark-probability' ) {
		$param{$field} = 1 / $val;
            }  else {
		$param{$field} = $val;
            }
        }
	$precedence[$i] = \%param;
    }

    return @precedence;
}

sub commands {
    my ( $self, $dev ) = @_;
    my $root = 1;
    my $precedence = $self->{_precedence};
    my $rate = getAutoRate( $self->{_rate}, $dev );

    # 1. setup DSMARK to convert DSCP to tc_index
    print "qdisc add dev eth0 root handle $root: dsmark indices 1 set_tc_index\n";

    # 2. use tcindex filter to convert tc_index to precedence
    print
 "filter add dev $dev parent $root: protocol ip prio 1 tcindex mask 0xe0 shift 5\n";

    print "qdisc add dev $dev parent $root: gred setup DPs 8 default 7\n";

    # set VQ parameters
    for ( my $i = 0 ; $i <= 7 ; $i++ ) {
	my $param = $precedence->[$i];
	my $qmin = $param->{'min-threshold'};
	my $qmax = $param->{'max-threshold'};
	my $prob = $param->{'mark-probability'};

        print "qdisc change dev $dev parent $root:$i gred";
        printf " limit %dK min %dK max %dK avpkt 1K", 4 * $qmax, $qmin, $qmax;
        printf " burst %d bandwidth %d DP %d probability %f\n",
          ( 2 * $qmin + $qmax ) / 3, $rate, $i, $prob;
    }
}

# Walk configuration tree and look for changed nodes
# The configuration system should do this but doesn't do it right
sub isChanged {
    my ( $self, $name ) = @_;
    my $config = new Vyatta::Config;

    $config->setLevel("qos-policy random-detect $name");

    return 'bandwidth' if ( $config->isChanged('bandwidth') );

    my %precedenceNodes = $config->listNodeStatus('precedence');
    while ( my ( $pred, $status ) = each %precedenceNodes ) {
        return "precedence $pred" if ( $status ne 'static' );

	my $defaults = $default_fields[0];
        foreach my $attr (keys %$defaults) {
            return "precedence $pred $attr"
              if ( $config->isChanged("precedence $pred $attr") );
        }
    }

    return;    # false
}

1;
