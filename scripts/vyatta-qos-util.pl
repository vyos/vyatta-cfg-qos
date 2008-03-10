#!/usr/bin/perl
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

use lib "/opt/vyatta/share/perl5/";
use VyattaQosUtil;
use Getopt::Long;

GetOptions(
    "rate=s"     => \$rate,
    "burst=s"    => \$burst,
    "protocol=s" => \$protocol,
    "dscp=s"	 => \$dsfield,
    "tos=s"	 => \$dsfield,
);

if ( defined $rate ) {
    my $r = VyattaQosUtil::getRate($rate);
    exit 0;
}

if ( defined $burst ) {
    my $b = VyattaQosUtil::getSize($burst);
    exit 0;
}

if ( defined $protocol ) {
    my $p = VyattaQosUtil::getProtocol($protocol);
    exit 0;
}

if ( defined $dsfield ) {
    my $d = VyattaQosUtil::getDsfield($dsfield);
    exit 0;
}

print <<EOF;
usage: vyatta-qos-util.pl --rate rate
       vyatta-qos-util.pl --burst size
       vyatta-qos-util.pl --protocol protocol
       vyatta-qos-util.pl --dscp tos|dsfield
EOF
exit 1;
