#! /usr/bin/perl
#
# Utility routines for validating input
# These functions don't change existing QoS parameters
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
use strict;

use lib "/opt/vyatta/share/perl5";
use Vyatta::Qos::Util qw( getPercent getRate getBurstSize getProtocol 
			  getDsfield getTime );
use Getopt::Long;

sub getPercentOrRate {
    my $rate = shift;
    return ( $rate =~ /%$/ ) ? getPercent($rate) : getRate($rate);
}

sub usage {
    print <<EOF;
  usage: 
      vyatta-qos-util.pl --percent value
      vyatta-qos-util.pl --percent-or-rate value
      vyatta-qos-util.pl --rate rate
      vyatta-qos-util.pl --time time
      vyatta-qos-util.pl --burst size
      vyatta-qos-util.pl --protocol protocol
      vyatta-qos-util.pl --dscp tos|dsfield
EOF
    exit 1;
}

my ($percent, $percentrate, $rate, $burst, $protocol, $dscp, $timeval);

GetOptions(
    "percent=s"         => \$percent,
    "percent-or-rate=s" => \$percentrate,
    "rate=s"            => \$rate,
    "burst=s"           => \$burst,
    "protocol=s"        => \$protocol,
    "dscp=s"            => \$dscp,
    "tos=s"             => \$dscp,
    "time=s"            => \$timeval,
) or usage();

getPercent($percent)		if defined($percent);
getPercentOrRate($percentrate)	if defined($percentrate);
getRate($rate)			if defined($rate);
getBurstSize($burst)		if defined($burst);
getProtocol($protocol)		if defined($protocol);
getDsfield($dscp)		if defined($dscp);
getTime($timeval)		if defined($timeval);
