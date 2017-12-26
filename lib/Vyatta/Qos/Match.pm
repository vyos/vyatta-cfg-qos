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

package Vyatta::Qos::Match;
require Vyatta::Config;
use Vyatta::Qos::Util qw(getIfIndex getDsfield getProtocol);

use strict;
use warnings;

sub getPort {
    my ( $str, $proto ) = @_;
    return unless defined($str);

    if ( $str =~ /^([0-9]+)|(0x[0-9a-fA-F]+)$/ ) {
        die "$str is not a valid port number\n"
          if ( $str <= 0 || $str > 65535 );
        return $str;
    }

    $proto = "tcp" unless $proto;
    my $port = getservbyname( $str, $proto );
    die "$str unknown $proto port name\n" unless $port;

    return $port;
}

sub new {
    my ( $that, $config ) = @_;
    my $self = {};
    my $class = ref($that) || $that;
    my $lastaf;

    bless $self, $class;

    # special case for match all
    unless ($config) {
	$self->{'ether'} = { protocol => 'all' };
	return $self;
    }

    foreach my $af (qw(ip ipv6 ether)) {
        next unless $config->exists($af);

        my %fields;

        if ( $af eq 'ether' ) {
            $fields{protocol} = $config->returnValue("ether protocol");
            $fields{src}      = $config->returnValue("ether source");
            $fields{dst}      = $config->returnValue("ether destination");
        } else {
            my $dsfield = $config->returnValue("$af dscp");
            my $ipprot  = $config->returnValue("$af protocol");
            my $src     = $config->returnValue("$af source address");
            my $dst     = $config->returnValue("$af destination address");
            my $sport   = $config->returnValue("$af source port");
            my $dport   = $config->returnValue("$af destination port");
            my $maxlen  = $config->returnValue("$af max-length");
            my $tcpsyn  = $config->exists("$af tcp syn");
            my $tcpack  = $config->exists("$af tcp ack");
        
            $fields{dsfield}  = getDsfield($dsfield) if $dsfield;
            $fields{protocol} = getProtocol($ipprot) if $ipprot;
            $fields{src}      = $src if $src;
            $fields{dst}      = $dst if $dst;
            $fields{sport}    = getPort( $sport, $ipprot ) if $sport;
            $fields{dport}    = getPort( $dport, $ipprot ) if $dport;
            $fields{maxlen}   = $maxlen if $maxlen;
            $fields{tcpsyn}   = $tcpsyn;
            $fields{tcpack}   = $tcpack;
            
            # Reject any protocol apart from tcp if tcp syn or tcp ack are set
            if($tcpsyn or $tcpack) {
                die "Protocol cannot be different from tcp" if defined $fields{protocol} and $fields{protocol} ne getProtocol('tcp');
                $fields{protocol} = getProtocol('tcp');
            }
        }

        # if the hash is empty then we didn't generate a match rule 
        # this usually means user left an uncompleted match in the config
        my @keys = keys(%fields);
        if ($#keys < 0) {
            return undef;
        }
        $self->{$af} = \%fields;

        die "Can not match on both $af and $lastaf protocol in same match\n"
          if $lastaf;
        $lastaf = $af;
    }

    my $vif = $config->returnValue("vif");
    $self->{_vif} = $vif;

    my $iif = $config->returnValue("interface");
    $self->{_indev} = getIfIndex($iif);

    my $fwmark = $config->returnValue("mark");
    $self->{_fwmark} = $fwmark;

    if ($lastaf) {
        die "Can not combine protocol and vlan tag match\n"
          if ($vif);
        die "Can not combine protocol and interface match\n"
          if ($iif);
    }

    return $self;
}

sub filter {
    my ( $self, $dev, $parent, $classid, $prio, $dsmark, $police ) = @_;

    # empty match
    return unless %{$self};

    # Special case for when dsmarking is used with ds matching
    # original dscp is saved in tc_index
    if ($dsmark) {
        foreach my $ipver (qw(ip ipv6)) {
            my $ip = $self->{$ipver};
            next unless $ip && $$ip{dsfield};

            printf "filter add dev %s parent %x: protocol %s prio %d",
	      $dev, $parent, $ipver, $prio;
            printf " handle %s tcindex classid %x:%x\n",
              $$ip{dsfield}, $parent, $classid;

            $prio += 1;
        }
        return;
    }

    my $fwmark = $self->{_fwmark};
    foreach my $proto (qw(ip ipv6 ether)) {
        my $p = $self->{$proto};
        next unless $p;

        printf "filter add dev %s parent %x: prio %d", $dev, $parent, $prio;
        if ( $proto eq 'ether' ) {
            my $type = $$p{protocol};
            $type = 'all' unless $type;

	        print " protocol $type u32";
            if ( defined( $$p{src} ) || defined( $$p{dst} ) ) {
                print " match ether src $$p{src}" if $$p{src};
                print " match ether dst $$p{dst}" if $$p{dst};
            } else {
                print " match u32 0 0";
            }
        } else {
            print " protocol all u32";

            # workaround inconsistent usage in tc u32 match
            my $sel = $proto;
            if ( $proto eq 'ipv6' ) {
                $sel = 'ip6';
                printf " match u16 0x%x 0x0ff0 at 0", hex( $$p{dsfield} ) << 4,
                  if $$p{dsfield};
            } else {
                print " match $sel dsfield $$p{dsfield} 0xff" if $$p{dsfield};
            }
            print " match $sel protocol $$p{protocol} 0xff" if $$p{protocol};

            print " match $sel src $$p{src}"            if $$p{src};
            print " match $sel sport $$p{sport} 0xffff" if $$p{sport};
            print " match $sel dst $$p{dst}"            if $$p{dst};
            print " match $sel dport $$p{dport} 0xffff" if $$p{dport};
            # Max Length :
            # Will match against total length of an IPv4 packet and payload length of an IPv6 packet.
            # IPv4 : match u16 0x0000 ~MAXLEN at 2
            # IPv6 : match u16 0x0000 ~MAXLEN at 4
            if ($$p{maxlen}) {
                if ( $proto eq 'ip' ) {
                    printf " match u16 0x0000 %#.4x at 2", 0xffff & ~int($$p{maxlen});
                } elsif ( $proto eq 'ipv6' ) {
                    printf " match u16 0x0000 %#.4x at 4", 0xffff & ~int($$p{maxlen});
                }
            }
            # TCP Flags :
            # Will match against specific TCP flags
            # We will assume the IPv4 header length is 20 bytes
            # We will assume the IPv6 packet is not using extension headers (hence a ip header length of 40 bytes)
            # TCP Flags are set on byte 13 of the TCP header.
            # IPv4 : match u8 X X at 33
            # IPv6 : match u8 X X at 53
            # with X = 0x02 for SYN and X = 0x10 for ACK
            if ($$p{tcpsyn} or $$p{tcpack}) {
                # Let's build the binary mask
                my $mask = 0;
                $mask |= 0x02 if $$p{tcpsyn};
                $mask |= 0x10 if $$p{tcpack};

                if ( $proto eq 'ip' ) {
                    printf " match u8 %#.2x %#.2x at 33", $mask, $mask;
                } elsif ( $proto eq 'ipv6' ) {
                    printf " match u8 %#.2x %#.2x at 53", $mask, $mask;
                }
            }
        }

        print " match mark $fwmark 0xff" if $fwmark;
        print " $police"                 if $police;
        printf " flowid %x:%x\n", $parent, $classid;
        return;
    }

    my $indev = $self->{_indev};
    my $vif   = $self->{_vif};
    if ( defined($vif) || defined($indev) ) {
        printf "filter add dev %s parent %x: prio %d", $dev, $parent, $prio;
        print " protocol all basic";
        print " match meta\(rt_iif eq $indev\)"        if $indev;
        print " match meta\(vlan mask 0xfff eq $vif\)" if $vif;
        print " match meta\(fwmark eq $fwmark\)"       if $fwmark;

        print " $police" if $police;
        printf " flowid %x:%x\n", $parent, $classid;
    }
    elsif ($fwmark) {
        printf "filter add dev %s parent %x: prio %d", $dev, $parent, $prio;
        printf " protocol all handle %d fw", $fwmark;
        print " $police" if $police;
        printf " flowid %x:%x\n", $parent, $classid;
    }
}

1;
