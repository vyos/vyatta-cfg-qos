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

GetOptions(
    "percent=s"         => sub { getPercent( $_[1] ); },
    "percent-or-rate=s" => sub { getPercentOrRate( $_[1] ); },
    "rate=s"            => sub { getRate( $_[1] ); },
    "burst=s"           => sub { getBurstSize( $_[1] ); },
    "protocol=s"        => sub { getProtocol( $_[1] ); },
    "dscp=s"            => sub { getDsfield( $_[1] ); },
    "tos=s"             => sub { getDsfield( $_[1] ); },
    "time=s"            => sub { getTime( $_[1] ); },
) or usage();
