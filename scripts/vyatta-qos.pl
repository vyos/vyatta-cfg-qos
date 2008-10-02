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
my ($check, $update, $applyChanges);
my @updateInterface = ();
my @deleteInterface = ();

my ($listPolicy, $deletePolicy);
my @createPolicy = ();

GetOptions(
    "check"		    => \$check,
    "apply-changes"         => \$applyChanges,
    "update-interface=s{3}" => \@updateInterface,
    "delete-interface=s{2}" => \@deleteInterface,

    "list-policy=s"         => \$listPolicy,
    "delete-policy=s"       => \$deletePolicy,
    "create-policy=s{2}"    => \@createPolicy,
);

my %policies = (
    'out' => {
	'traffic-shaper' => 'VyattaQosTrafficShaper',
	'fair-queue'     => 'VyattaQosFairQueue',
	'rate-limit'     => 'VyattaQosRateLimiter',
	'drop-tail'	 => 'VyattaQosDropTail',
    },
    'in' => {
	'traffic-limiter' => 'VyattaQosTrafficLimiter',
    }
);

# class factory for policies
sub make_policy {
    my ($config, $type, $name, $direction) = @_;
    my $class;

    if ($direction) {
	$class = $policies{$direction}{$type};
    } else {
	foreach $direction (keys %policies) {
	    $class = $policies{$direction}{$type};
	    last if defined $class;
	}
    }

    # This means template exists but we don't know what it is.
    if (! defined $class) {
	foreach $direction (keys %policies) {
	    die "QoS policy $name is type $type and is only valid for $direction\n"
		if defined $policies{$direction}{$type};
	}
	die "QoS policy $name has not been created\n";
    }

    my $location = "$class.pm";
    require $location;

    $config->setLevel("qos-policy $type $name");
    return $class->new($config, $name, $direction);
}

## list defined qos policy names
sub list_policy {
    my $direction = shift;
    my $config = new VyattaConfig;
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
	    die "bad direction $direction";
	}
    }
}

## update_interface('eth0', 'out', 'my-shaper')
# update policy to interface
sub update_interface {
    my ($interface, $direction, $name ) = @_;
    my $config = new VyattaConfig;

    $config->setLevel('qos-policy');
    foreach my $type ( $config->listNodes() ) {
        if ( $config->exists("$type $name") ) {
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

            $shaper->commands($out, $interface);
	    if (! close $out && ! defined $debug) {
		# cleanup any partial commands
		delete_interface($interface, $direction);

		# replay commands to stdout
		open $out, '>-';
		$shaper->commands($out, $interface, $direction);
		close $out;
		die "TC command failed.";
	    }
            exit 0;
        }
    }

    die "Unknown qos-policy $name\n";
}

sub using_policy {
    my ($config, $name, $interface) = @_;
    my @inuse = ();

    foreach my $dir ( $config->listNodes("$interface qos-policy") ) {
	my $policy = $config->returnValue("$interface qos-policy $dir");
	if ($policy eq $name) {
	    push @inuse, "$interface $dir";
	}
    }
    return @inuse;
}

sub interfaces_using {
    my ($name) = @_;
    my $config = new VyattaConfig;
    my @affected = ();

    $config->setLevel('interfaces');
    foreach my $type ( $config->listNodes() ) {
	foreach my $interface ( $config->listNodes($type) ) {
	    push @affected, using_policy($config, $name, "$type $interface");

	    if ($type eq 'ethernet') {
		foreach my $vif ( $config->listNodes("$type $interface vif") ) {
		    push @affected, using_policy($config, $name, "$type $interface vif $vif");
		}
	    }

	    if ($type eq 'adsl') {
		foreach my $pvc ( $config->listNodes("adsl $interface pvc") ) {
		    foreach my $pvctype ( $config->listNodes("adsl $interface pvc $pvc") ) {
			foreach my $vc ( $config->listNodes("adsl $interface pvc $pvc $pvctype") ) {
			    push @affected, using_policy($config, $name, 
						      "adsl $interface pvc $pvc $pvctype $vc");
			}
		    }
		}
	    }
	}
    }

    return @affected;
}

sub etherName {
    my $eth = shift;

    if ($_ =~ /vif/) {
	shift; 
	$eth .= $_;
    }
    return $eth;
}

sub serialName {
    my $wan = shift;
    # XXX add vif
    return $wan;
}

sub adslName {
    # adsl-name pvc pvc-num ppp-type id
    my (undef, undef, undef, $type, $id) = @_;

    return $type . $id;
}

# Handle mapping of interface types to device names
my %interfaceTypes = (
    'ethernet'	=> \&etherName,
    'serial'	=> \&serialName,
    'adsl'	=> \&adslName,
    );

sub delete_policy {
    my ($name) = @_;
    my @inuse = interfaces_using($name);

    if ( @inuse ) {
	foreach my $usage (@inuse) {
	    warn "QoS policy $name used by $usage\n";
	}
	# can't delete active policy
	die "Must delete QoS policy from interfaces before deleting rules\n";
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

sub apply_changes {
    my $config = new VyattaConfig;

    $config->setLevel('qos-policy');
    foreach my $policy ($config->listNodes()) {
	foreach my $name ($config->listNodes($policy)) {
	    my $shaper = make_policy($config, $policy, $name);

	    if ($shaper->isChanged($name)) {
		foreach my $cfgpath (interfaces_using($name)) {
		    my @elements = split / /, $cfgpath;
		    my $direction = pop @elements;  # out, in, ...
		    my $type = shift @elements;     # ethernet, serial, ...
		    my $interface = $interfaceTypes{$type};
		    my $device = $interface->(@elements);

		    update_interface($device, $direction, $name);
		}
	    }
	}
    }
}

if ($check) {
    check_conflict();
    exit 0;
}

if ( $listPolicy ) {
    list_policy($listPolicy);
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

if ( $deletePolicy ) {
    delete_policy($deletePolicy);
    exit 0;
} 

if ( $applyChanges ) {
    apply_changes();
    exit 0;
}

print <<EOF;
usage: vyatta-qos.pl --check
       vyatta-qos.pl --list-policy

       vyatta-qos.pl --create-policy policy-type policy-name
       vyatta-qos.pl --delete-policy policy-name
       vyatta-qos.pl --apply-changes policy-type policy-name

       vyatta-qos.pl --update-interface interface direction policy-name
       vyatta-qos.pl --delete-interface interface direction

EOF
exit 1;
