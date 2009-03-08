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
	'drop-tail'	   => 'DropTail',
	'network-emulator' => 'NetworkEmulator',
    },
    'in' => {
	'traffic-limiter' => 'TrafficLimiter',
    }
);

# class factory for policies
sub make_policy {
    my ($config, $type, $name, $direction) = @_;
    my $policy_type;

    if ($direction) {
	$policy_type = $policies{$direction}{$type};
    } else {
	foreach my $direction (keys %policies) {
	    $policy_type = $policies{$direction}{$type};
	    last if defined $policy_type;
	}
    }

    # This means template exists but we don't know what it is.
    if (! defined $policy_type) {
	foreach my $direction (keys %policies) {
	    die "QoS policy $name is type $type and is only valid for $direction\n"
		if defined $policies{$direction}{$type};
	}
	die "QoS policy $name has not been created\n";
    }
    $config->setLevel("qos-policy $type $name");

    my $location = "Vyatta/Qos/$policy_type.pm";
    my $class = "Vyatta::Qos::$policy_type";

    require $location;

    return $class->new($config, $name, $direction);
}

## list defined qos policy names
sub list_policy {
    my $direction = shift;
    my $config = new Vyatta::Config;
    my @nodes  = ();

    $config->setLevel('qos-policy');
    foreach my $type ( $config->listNodes() ) {
	next unless defined $policies{$direction}{$type};
	foreach my $name ( $config->listNodes($type) ){
	    push @nodes, $name;
	}
    }

    print join( ' ', @nodes ), "\n";
}

## delete_interface('eth0', 'out')
# remove all filters and qdisc's
sub delete_interface {
    my ($interface, $direction ) = @_;

    for ($direction) {
	# delete old qdisc - silence error if no qdisc loaded
	if (/^out$/) {
	    qx(sudo /sbin/tc qdisc del dev "$interface" root 2>/dev/null);
	} elsif (/^in$/) {
	    qx(sudo /sbin/tc qdisc del dev "$interface" parent ffff: 2>/dev/null);
	} else {
	    croak "bad direction $direction";
	}
    }
}

## start_interface('ppp0')
# reapply qos policy to interface
sub start_interface {
    my $ifname = shift;
    my $interface = new Vyatta::Interface($ifname);

    die "Unknown interface type: $ifname" unless $interface;
    my $config = new Vyatta::Config;
    $config->setLevel($interface->path() . ' qos-policy');

    foreach my $direction ( $config->listNodes( ) ) {
	my $policy = $config->returnValue($direction);
	next unless $policy;

	update_interface($ifname, $direction, $policy);
    }
}

## update_interface('eth0', 'out', 'my-shaper')
# update policy to interface
sub update_interface {
    my ($interface, $direction, $name ) = @_;
    my $config = new Vyatta::Config;

    my @policies = $config->listNodes('qos-policy');
    foreach my $type ( @policies ) {
	next if (! $config->exists("$type $name"));
	my $shaper = make_policy($config, $type, $name, $direction);

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

	$shaper->commands($out, $interface, $direction);
	if (! close $out && ! defined $debug) {
	    # cleanup any partial commands
	    delete_interface($interface, $direction);

	    # replay commands to stdout
	    open $out, '>-';
	    $shaper->commands($out, $interface, $direction);
	    close $out;
	    die "TC command failed.";
	}
	return;
    }

    die "Unknown qos-policy $name\n";
}

# return array of names using given qos-policy
sub interfaces_using {
    my $policy = shift;
    my $config = new Vyatta::Config;
    my @inuse = ();
    
    foreach my $name (getInterfaces()) {
	my $intf = new Vyatta::Interface($name);
	next unless $intf;

	$config->setLevel( $intf->path() );
	push @inuse, $name if ($config->exists("qos-policy $policy"));
    }
    return @inuse;
}

sub delete_policy {
    my ($name) = @_;
    my @inuse = interfaces_using($name);

    die "QoS policy still in use on ", join(' ', @inuse), "\n"
	if ( @inuse );
}

sub name_conflict {
    my $config = new Vyatta::Config;
    my %other = ();

    $config->setLevel("qos-policy");
    foreach my $type ( $config->listNodes() ) {
	foreach my $name ( $config->listNodes($type) ) {
	    my $conflict = $other{$name};
	    if ($conflict) {
		warn "Policy $name used by $conflict and $type\n";
		return $name;
	    }
	    $other{$name} = $type;
	}
    }
    return;
}

sub create_policy {
    my ($shaper, $name) = @_;
    my $config = new Vyatta::Config;

    exit 1 if name_conflict();

    make_policy($config, $shaper, $name);
}

sub apply_changes {
    my $config = new Vyatta::Config;

    my @policies = $config->listNodes('qos-policy');
    foreach my $policy (@policies) {
	foreach my $name ($config->listNodes($policy)) {
	    my $shaper = make_policy($config, $policy, $name);

	    next unless ($shaper->isChanged($name));

	    foreach my $device (interfaces_using($name)) {
		my $intf = new Vyatta::Interface($device);
		$config->setLevel($intf->path());
		foreach my $direction ($config->listNodes('qos-policy')) {
		    next unless $config->exists("qos-policy $direction $name");

		    update_interface($device, $direction, $name);
		}
	    }
	}
    }
}

sub usage {
	print <<EOF;
usage: vyatta-qos.pl --list-policy
       vyatta-qos.pl --apply

       vyatta-qos.pl --create-policy policy-type policy-name
       vyatta-qos.pl --delete-policy policy-name

       vyatta-qos.pl --update-interface interface direction policy-name
       vyatta-qos.pl --delete-interface interface direction

EOF
	exit 1;
}

my @updateInterface = ();
my @deleteInterface = ();
my @createPolicy = ();

my ($apply, $start);

GetOptions(
    "apply"	            => \$apply,
    "start-interface=s"	    => \$start,
    "update-interface=s{3}" => \@updateInterface,
    "delete-interface=s{2}" => \@deleteInterface,

    "list-policy=s"         => sub { list_policy( $_[1] ); },
    "delete-policy=s"       => sub { delete_policy( $_[1] ); },
    "create-policy=s{2}"    => \@createPolicy,
) or usage();

apply_changes() if $apply;

delete_interface(@deleteInterface) if ( $#deleteInterface == 1 );
update_interface(@updateInterface) if ( $#updateInterface == 2 );
start_interface( $start ) if $start;
create_policy(@createPolicy)	   if ( $#createPolicy == 1);
