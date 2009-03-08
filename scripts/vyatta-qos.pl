#!/usr/bin/perl
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

use lib "/opt/vyatta/share/perl5";
use strict;
use warnings;

use Carp;
use Vyatta::Misc;
use Vyatta::Config;
use Getopt::Long;

my $debug = $ENV{'QOS_DEBUG'};

my %policies = (
    'out' => {
        'traffic-shaper'   => 'TrafficShaper',
        'fair-queue'       => 'FairQueue',
        'rate-limit'       => 'RateLimiter',
        'drop-tail'        => 'DropTail',
        'network-emulator' => 'NetworkEmulator',
    },
    'in' => { 'traffic-limiter' => 'TrafficLimiter', }
);

# find policy for name - also check for duplicates
## find_policy('limited')
sub find_policy {
    my $name   = shift;
    my $config = new Vyatta::Config;

    $config->setLevel('qos-policy');
    my @policy = grep { $config->exists("$_ $name") } $config->listNodes();

    die "Policy name \"$name\" conflict, used by: ", join( ' ', @policy ), "\n"
      if ( $#policy > 0 );

    return $policy[0];
}

# class factory for policies
## make_policy('traffic-shaper', 'limited', 'out')
sub make_policy {
    my ( $type, $name, $direction ) = @_;
    my $policy_type;

    if ($direction) {
        $policy_type = $policies{$direction}{$type};
    }
    else {
        foreach my $direction ( keys %policies ) {
            $policy_type = $policies{$direction}{$type};
            last if defined $policy_type;
        }
    }

    # This means template exists but we don't know what it is.
    unless ($policy_type) {
        foreach my $direction ( keys %policies ) {
            die
"QoS policy $name is type $type and is only valid for $direction\n"
              if $policies{$direction}{$type};
        }
        die "QoS policy $name has not been created\n";
    }

    my $config = new Vyatta::Config;
    $config->setLevel("qos-policy $type $name");

    my $location = "Vyatta/Qos/$policy_type.pm";
    my $class    = "Vyatta::Qos::$policy_type";

    require $location;

    return $class->new( $config, $name, $direction );
}

## list defined qos policy names for a direction
sub list_policy {
    my $config = new Vyatta::Config;
    $config->setLevel('qos-policy');

    while ( my $direction = shift ) {
        my @types =
          grep { defined $policies{$direction}{$_} } $config->listNodes();
        print join( ' ', @types );
    }
}

## delete_interface('eth0', 'out')
# remove all filters and qdisc's
sub delete_interface {
    my ( $interface, $direction ) = @_;

    for ($direction) {

        # delete old qdisc - silence error if no qdisc loaded
        if (/^out$/) {
            qx(sudo /sbin/tc qdisc del dev "$interface" root 2>/dev/null);
        }
        elsif (/^in$/) {
qx(sudo /sbin/tc qdisc del dev "$interface" parent ffff: 2>/dev/null);
        }
        else {
            croak "bad direction $direction";
        }
    }
}

## start_interface('ppp0')
# reapply qos policy to interface
sub start_interface {
    while ( my $ifname = shift ) {
        my $interface = new Vyatta::Interface($ifname);
        die "Unknown interface type: $ifname" unless $interface;

        my $config = new Vyatta::Config;
        $config->setLevel( $interface->path() . ' qos-policy' );

        foreach my $direction ( $config->listNodes() ) {
            my $policy = $config->returnValue($direction);
            next unless $policy;

            update_interface( $ifname, $direction, $policy );
        }
    }
}

## update_interface('eth0', 'out', 'my-shaper')
# update policy to interface
sub update_interface {
    my ( $device, $direction, $name ) = @_;
    my $policy = find_policy($name);
    die "Unknown qos-policy $name\n" unless $policy;

    my $shaper = make_policy( $policy, $name, $direction );
    exit 1 unless $shaper;

    # Remove old policy
    delete_interface( $device, $direction );

    # When doing debugging just echo the commands
    my $out;
    if ( defined $debug ) {
        open $out, '>-'
          or die "can't open stdout: $!";
    }
    else {
        open $out, "|-"
          or exec qw:sudo /sbin/tc -batch -:
          or die "Tc setup failed: $!\n";
    }

    $shaper->commands( $out, $device, $direction );
    if ( !close $out && !defined $debug ) {

        # cleanup any partial commands
        delete_interface( $device, $direction );

        # replay commands to stdout
        open $out, '>-';
        $shaper->commands( $out, $device, $direction );
        close $out;
        die "TC command failed.";
    }
}

# return array of names using given qos-policy
sub interfaces_using {
    my $policy = shift;
    my $config = new Vyatta::Config;
    my @inuse  = ();

    foreach my $name ( getInterfaces() ) {
        my $intf = new Vyatta::Interface($name);
        next unless $intf;

        $config->setLevel( $intf->path() );
        push @inuse, $name if ( $config->exists("qos-policy $policy") );
    }
    return @inuse;
}

# check if policy name(s) are still in use
sub delete_policy {
    while ( my $name = shift ) {
        my @inuse = interfaces_using($name);

        die "QoS policy still in use on ", join( ' ', @inuse ), "\n"
          if (@inuse);
    }
}

sub create_policy {
    my ( $policy, $name ) = @_;
    find_policy($name);

    # Check policy for validity
    my $shaper = make_policy( $policy, $name );
    exit 1 unless $shaper;
}

# Configuration changed, reapply to all interfaces.
sub apply_policy {
    my $config = new Vyatta::Config;

    while ( my $name = shift ) {
        foreach my $device ( interfaces_using($name) ) {
            my $intf = new Vyatta::Interface($device);

            $config->setLevel( $intf->path() );
            foreach my $direction ( $config->listNodes('qos-policy') ) {
                next unless $config->exists("qos-policy $direction $name");

                update_interface( $device, $direction, $name );
            }
        }
    }
}

sub usage {
    print <<EOF;
usage: vyatta-qos.pl --list-policy direction
       vyatta-qos.pl --create-policy policy-type policy-name
       vyatta-qos.pl --delete-policy policy-name
       vyatta-qos.pl --apply-policy policy-name

       vyatta-qos.pl --update-interface interface direction policy-name
       vyatta-qos.pl --delete-interface interface direction

EOF
    exit 1;
}

my @updateInterface = ();
my @deleteInterface = ();
my @listPolicy      = ();
my @createPolicy    = ();
my @applyPolicy     = ();
my @deletePolicy    = ();
my @startList       = ();

GetOptions(
    "start-interface=s"     => \@startList,
    "update-interface=s{3}" => \@updateInterface,
    "delete-interface=s{2}" => \@deleteInterface,

    "list-policy=s"      => \@listPolicy,
    "delete-policy=s"    => \@deletePolicy,
    "create-policy=s{2}" => \@createPolicy,
    "apply-policy=s"     => \@applyPolicy,
) or usage();

delete_interface(@deleteInterface) if ( $#deleteInterface == 1 );
update_interface(@updateInterface) if ( $#updateInterface == 2 );
start_interface(@startList)        if (@startList);
list_policy(@listPolicy)           if (@listPolicy);
create_policy(@createPolicy)       if ( $#createPolicy == 1 );
delete_policy(@deletePolicy)       if (@deletePolicy);
apply_policy(@applyPolicy)         if (@applyPolicy);

