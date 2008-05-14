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

use lib "/opt/vyatta/share/perl5/";
use VyattaConfig;
use strict;

use Getopt::Long;

my $debug = $ENV{'QOS_DEBUG'};
my $check = undef;
my @updateInterface = ();
my @deleteInterface = ();

my $listPolicy = undef;
my $deletePolicy = undef;
my @createPolicy = ();
my @updatePolicy = ();

GetOptions(
    "check"		    => \$check,
    "update-interface=s{3}" => \@updateInterface,
    "delete-interface=s{2}" => \@deleteInterface,

    "list-policy"           => \$listPolicy,
    "delete-policy=s"       => \$deletePolicy,
    "create-policy=s{2}"    => \@createPolicy,
    "update-policy=s{2}"    => \@updatePolicy,
);

# class factory for policies
# TODO use hierarcy (ie VyattaQos::TrafficShaper)
#      and reference to object, not string dynamic binding
my %policies = (
    'traffic-shaper' => "VyattaQosTrafficShaper",
    'fair-queue'     => "VyattaQosFairQueue",
    'rate-limit'     => "VyattaQosRateLimiter",
);
use VyattaQosTrafficShaper;
use VyattaQosFairQueue;
use VyattaQosRateLimiter;

sub make_policy {
    my ($config, $type, $name) = @_;
    my $class = $policies{$type};

    # This means template exists but we don't know what it is.
    defined $class or die "Unknown policy type $type";

    $config->setLevel("qos-policy $type $name");

    return $class->new($config, $name);
}

## list defined qos policy names
sub list_policy {
    my $config = new VyattaConfig;
    my @nodes  = ();

    $config->setLevel('qos-policy');
    foreach my $type ( $config->listNodes() ) {
        foreach my $name ( $config->listNodes($type) ) {
            push @nodes, $name;
        }
    }

    print join( ' ', @nodes ), "\n";
}

## delete_interface('eth0', 'out')
# remove all filters and qdisc's
sub delete_interface {
    my ($interface, $direction ) = @_;

    if ($direction eq "out" ) {
        # delete old qdisc - will give error if no policy in place
	qx(sudo /sbin/tc qdisc del dev "$interface" root 2>/dev/null);
    }
}

## update_interface('eth0', 'out', 'my-shaper')
# update policy to interface
sub update_interface {
    my ($interface, $direction, $name ) = @_;
    my $config = new VyattaConfig;

    ( $direction eq "out" ) or die "Only out direction supported";

    $config->setLevel('qos-policy');
    foreach my $type ( $config->listNodes() ) {
        if ( $config->exists("$type $name") ) {
	    my $shaper = make_policy($config, $type, $name);

	    # Remove old policy
	    delete_interface($interface, $direction);

	    # When doing debugging just echo the commands
	    my $out;
	    if (defined $debug) {
		open $out, '>-'
		    or die "can't open stdout: $!";
	    } else {
		open $out, "|-" or exec qw:sudo /sbin/tc -batch -:
		    or die "Tc setup failed: $!\n";
	    }

            $shaper->commands($out, $interface);
	    if (! close $out && ! defined $debug) {
		# cleanup any partial commands
		delete_interface($interface, $direction);

		# replay commands to stdout
		open $out, '>-';
		$shaper->commands($out, $interface);
		close $out;
		die "TC command failed.";
	    }
            exit 0;
        }
    }

    die "Unknown qos-policy $name\n";
}

sub delete_policy {
    my ($name) = @_;
    my $config = new VyattaConfig;

    $config->setLevel("interfaces ethernet");
    foreach my $interface ( $config->listNodes() ) {
	foreach my $direction ( $config->listNodes("$interface qos-policy") ) {
	    if ($config->returnValue("$interface qos-policy $direction") eq $name) {
		# can't delete active policy
		die "Qos policy $name still in use on ethernet $interface $direction\n";
	    }
	}
    }
}

sub check_conflict {
    my $config = new VyattaConfig;
    my %other = ();

    $config->setLevel("qos-policy");
    foreach my $type ( $config->listNodes() ) {
	foreach my $name ( $config->listNodes($type) ) {
	    my $conflict = $other{$name};
	    die "Policy $name used by $conflict and $type\n" if ($conflict);
	    $other{$name} = $type;
	}
    }
}

sub create_policy {
    my ($shaper, $name) = @_;
    my $config = new VyattaConfig;

    # Syntax check
    make_policy($config, $shaper, $name);
}

sub update_policy {
    my ($shaper, $name) = @_;
    my $config = new VyattaConfig;

    # Syntax check
    make_policy($config, $shaper, $name);

    $config->setLevel("interfaces ethernet");
    foreach my $interface ( $config->listNodes() ) {
	foreach my $direction ( $config->listNodes("$interface qos-policy") ) {
	    if ($config->returnValue("$interface qos-policy $direction") eq $name) {
		update_interface($interface, $direction, $name);
	    }
	}
    }
}

if ($check) {
    check_conflict();
    exit 0;
}

if ( $listPolicy ) {
    list_policy();
    exit 0;
}

if ( $#deleteInterface == 1 ) {
    delete_interface(@deleteInterface);
    exit 0;
}

if ( $#updateInterface == 2 ) {
    update_interface(@updateInterface);
    exit 0;
}

if ( $#createPolicy == 1) {
    create_policy(@createPolicy);
    exit 0;
}

if ( $#updatePolicy == 1) {
    update_policy(@updatePolicy);
    exit 0;
}

if ( $deletePolicy ) {
    delete_policy($deletePolicy);
    exit 0;
}

print <<EOF;
usage: vyatta-qos.pl --check
       vyatta-qos.pl --list-policy
       vyatta-qos.pl --create-policy policy-type policy-name
       vyatta-qos.pl --delete-policy policy-name
       vyatta-qos.pl --update-policy policy-type policy-name
       vyatta-qos.pl --update-interface interface direction policy-name
       vyatta-qos.pl --delete-interface interface direction

EOF
exit 1;
