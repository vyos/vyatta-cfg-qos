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
	my %pred;

	$config->setLevel("$level precedence $i");

	# Compute some sane defaults based on predence and max-threshold
	$pred{qmax} = $config->returnValue('maximum-threshold');
	$pred{qmax} = 18 unless $pred{qmax};
	
	$pred{qmin} = $config->returnValue('minimum-threshold');
	if ($pred{qmin}) {
	    die "min-threshold: $pred{qmin} >= max-threshold: $pred{qmax}\n"
		if ($pred{qmin} >= $pred{qmax});
	} else {
	    $pred{qmin} = ((9 + $i) * $pred{qmax})/ 18;
	}

	$pred{qlim} = $config->returnValue('queue-limit');
	if ($pred{qlim}) {
	    die "queue-limit: $pred{qlim} < max-threshold: $pred{qmax}\n"
		if ($pred{qlim} < $pred{qmax});
	} else {
	    $pred{qlim} = 4 * $pred{qmax};
	}

	my $mp = $config->returnValue('mark-probablilty');
	$pred{prob} = (defined $mp) ? (1 / $mp) : (1 / 10);

	my $avgpkt = $config->returnValue('average-packet');
	$pred{avpkt} = (defined $avgpkt) ? $avgpkt : 1024;

	$precedence[$i] = \%pred;
    }

    return @precedence;
}

sub commands {
    my ( $self, $dev ) = @_;
    my $root = 1;
    my $precedence = $self->{_precedence};
    my $rate = getAutoRate( $self->{_rate}, $dev );

    # 1. setup DSMARK to convert DSCP to tc_index
    printf "qdisc add dev %s root handle %x:0 dsmark indices 8 set_tc_index\n",
    	$dev, $root;

    # 2. use tcindex filter to convert tc_index to precedence
    #
    #  Precedence Field: the three leftmost bits in the TOS octet of an IPv4
    #   header.

    printf  "filter add dev %s parent %x:0 protocol ip prio 1 ",
	    $dev, $root;
    print "tcindex mask 0xe0 shift 5\n";

    # 3. Define GRED with unmatched traffic going to index 0
    printf "qdisc add dev %s parent %x:0 handle %x:0 gred ",
	    $dev, $root, $root+1;
    print "setup DPs 8 default 0 grio\n";

    # set VQ parameters
    for ( my $i = 0 ; $i <= 7 ; $i++ ) {
	my $pred = $precedence->[$i];
	my $avg  = $pred->{avpkt};
	my $burst = ( 2 * $pred->{qmin} + $pred->{qmax} ) / 3;

        printf "qdisc change dev %s handle %x:0 gred", $dev, $root+1, $i;
        printf " limit %d min %d max %d avpkt %d",
		$pred->{qlim} * $avg, $pred->{qmin} * $avg,
		$pred->{qmax} * $avg, $avg;

        printf " burst %d bandwidth %d probability %f DP %d prio %d\n",
		$burst, $rate, $pred->{prob}, $i, 8-$i;
    }
}

1;
