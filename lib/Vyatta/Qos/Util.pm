# QoS utility functions
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
package Vyatta::Qos::Util;
use strict;
use warnings;

our @EXPORT =
  qw(getRate getPercent getBurstSize getProtocol getDsfield getTime getAutoRate);
our @EXPORT_OK = qw(getIfIndex);
use base qw(Exporter);

sub get_num {
    use POSIX qw(strtod);
    my ($str) = @_;
    return unless defined($str);

    # remove leading/trailing spaces
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;

    $! = 0;
    my ( $num, $unparsed ) = strtod($str);
    if ( ( $unparsed == length($str) ) || $! ) {
        return;    # undefined (bad input)
    }

    if ( $unparsed > 0 ) { return $num, substr( $str, -$unparsed ); }
    else                 { return $num; }
}

## get_rate("10mbit")
# convert rate specification to number
# from tc/tc_util.c

my %rates = (
    'bit'   => 1,
    'kibit' => 1024,
    'kbit'  => 1000.,
    'mibit' => 1048576.,
    'mbit'  => 1000000.,
    'gibit' => 1073741824.,
    'gbit'  => 1000000000.,
    'tibit' => 1099511627776.,
    'tbit'  => 1000000000000.,
    'bps'   => 8.,
    'kibps' => 8192.,
    'kbps'  => 8000.,
    'mibps' => 8388608.,
    'mbps'  => 8000000.,
    'gibps' => 8589934592.,
    'gbps'  => 8000000000.,
    'tibps' => 8796093022208.,
    'tbps'  => 8000000000000.,
);

# Rate can be something like "auto" or "10.2mbit"
sub getAutoRate {
    my ( $rate, $dev ) = @_;

    if ( $rate eq "auto" ) {
        $rate = interfaceRate($dev);
        if ( !defined $rate ) {
            print STDERR
              "Interface $dev speed cannot be determined (assuming 10mbit)\n";
            $rate = 10000000;
        }
    } else {
        $rate = getRate($rate);
    }

    return $rate;
}

sub getRate {
    my $rate = shift;
    defined $rate
      or die "Rate not defined";

    my ( $num, $suffix ) = get_num($rate);
    defined $num
      or die "$rate is not a valid bandwidth (not a number)\n";

    die "Bandwidth of zero is not allowed\n"
	if ($num == 0);

    die "$rate is not a valid bandwidth (negative value)\n"
	if ($num < 0);

    if ( defined $suffix ) {
        my $scale = $rates{ lc $suffix };

        if ( defined $scale ) {
            return $num * $scale;
        }

        die "$rate is not a valid bandwidth (unknown scale suffix)\n";
    } else {

        # No suffix implies Kbps just as IOS
        return $num * 1000;
    }
}

sub getPercent {
    my $percent = shift;
    my ( $num, $suffix ) = get_num($percent);

    if ( defined $suffix && $suffix ne '%' ) {
        die "$percent incorrect suffix (expect %)\n";
    } elsif ( !defined $num ) {
        die "$percent is not a valid percent (not a number)\n";
    } elsif ( $num < 0 ) {
        die "$percent is not a acceptable percent (negative value)\n";
    } elsif ( $num > 100 ) {
        die "$percent is not a acceptable percent (greater than 100%)\n";
    } else {
        return $num;
    }
}

# Default time units for tc are usec.
my %timeunits = (
    's'     => 1000000,
    'sec'   => 1000000,
    'secs'  => 1000000,
    'ms'    => 1000,
    'msec'  => 1000,
    'msecs' => 1000,
    'us'    => 1,
    'usec'  => 1,
    'usecs' => 1,
);

sub getTime {
    my $time = shift;
    my ( $num, $suffix ) = get_num($time);

    defined $num
      or die "$time is not a valid time interval (not a number)\n";
    ( $num >= 0 )
      or die "$time is not a valid time interval (negative value)\n";

    return $num * 1000 unless $suffix; # No suffix implies ms

    my $scale = $timeunits{ lc $suffix };
    die "$time is not a valid time interval (unknown suffix)\n"
	unless $scale;

    return $num * $scale;
}

my %scales = (
    'b'    => 1,
    'k'    => 1024,
    'kb'   => 1024,
    'kbit' => 1024 / 8,
    'm'    => 1024 * 1024,
    'mb'   => 1024 * 1024,
    'mbit' => 1024 * 1024 / 8,
    'g'    => 1024 * 1024 * 1024,
    'gb'   => 1024 * 1024 * 1024,
);

sub getBurstSize {
    my $size = shift;
    my ( $num, $suffix ) = get_num($size);

    defined $num
      or die "$size is not a valid burst size (not a number)\n";

    ( $num >= 0 )
      or die "$size is not a valid burst size (negative value)\n";

    return $num unless $suffix;

    my $scale = $scales{ lc $suffix };
    defined $scale
	or die "$size is not a valid burst size (unknown scale suffix)\n";

    return $num * $scale;
}

sub getProtocol {
    my ($str) = @_;

    defined $str or return;
    if ( $str =~ /^([0-9]+)|(0x[0-9a-fA-F]+)$/ ) {
        if ( $str <= 0 || $str > 255 ) {
            die "$str is not a valid protocol number\n";
        }
        return $str;
    }

    my ( $name, $aliases, $proto ) = getprotobyname($str);
    die "\"$str\" unknown protocol\n"
      unless $proto;
    die "$name is not usable as an IP protocol match\n"
      if ( $proto == 0 );

    return $proto;
}

# Parse /etc/iproute/rt_dsfield
# return a hex string "0x10" or undefined
sub getDsfield {
    my ($str)      = @_;
    my $match      = undef;
    my $dsFileName = '/etc/iproute2/rt_dsfield';

    defined $str or return;

    # match number (or hex)
    if ( $str =~ /^([0-9]+)|(0x[0-9a-fA-F]+)$/ ) {
        if ( $str < 0 || $str > 63 ) {
            die "$str is not a valid DSCP value\n";
        }

        # convert DSCP value to header value used by iproute
        return $str << 2;
    }

    open my $ds, '<', $dsFileName || die "Can't open $dsFileName, $!\n";
    while (<$ds>) {
        next if /^#/;
        chomp;
        my ( $value, $name ) = split;
        if ( $str eq $name ) {
            $match = $value;
            last;
        }
    }
    close($ds) or die "read $dsFileName error\n";

    ( defined $match ) or die "\"$str\" unknown DSCP value\n";
    return $match;
}

sub getIfIndex {
    my ($str) = @_;

    defined $str or return;
    open my $sysfs, "<",
      "/sys/class/net/$str/ifindex" || die "Unknown interface $str\n";
    my $ifindex = <$sysfs>;
    close($sysfs) or die "read sysfs error\n";
    chomp $ifindex;
    return $ifindex;
}

## interfaceRate("eth0")
# return result in bits per second
sub interfaceRate {
    my ($interface) = @_;
    my $speed;
    my $config = new Vyatta::Config;

    $config->setLevel("interfaces ethernet");
    if ( $config->exists("$interface") ) {
        $speed = $config->returnValue("$interface speed");
        if ( defined($speed) && $speed ne "auto" ) {
            return $speed * 1000000;
        }
    }

    # During boot it may take time for auto-negotiation
    for ( my $retries = 0 ; $retries < 5 ; $retries++ ) {
        $speed = ethtoolRate($interface);
        if ( defined $speed ) {
            last;
        }
        sleep 1;
    }

    return $speed;
}

## ethtoolRate("eth0")
# Fetch actual rate using ethtool and format to valid tc rate
sub ethtoolRate {
    my $dev  = shift;
    my $rate = undef;

    # Get rate of real device (ignore vlan)
    $dev =~ s/\.[0-9]+$//;

    open( my $ethtool, '-|', "/sbin/ethtool $dev 2>/dev/null" )
      or die "ethtool failed: $!\n";

    # ethtool produces:
    #
    # Settings for eth1:
    # Supported ports: [ TP ]
    # ...
    # Speed: 1000Mb/s
    while (<$ethtool>) {
        my @line = split;
        if ( $line[0] =~ /^Speed:/ ) {
            if ( $line[1] =~ /[0-9]+Mb\/s/ ) {
                $rate = $line[1];
                $rate =~ s#Mb/s#000000#;
            }
            last;
        }
    }
    close $ethtool;
    return $rate;
}

1;
