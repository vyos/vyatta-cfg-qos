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
use Vyatta::Config;
use strict;

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
	    die "bad direction $direction";
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

    $config->setLevel('qos-policy');
    foreach my $type ( $config->listNodes() ) {
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

sub using_policy {
    my ($config, $name, $path) = @_;
    my @inuse = ();

    foreach my $dir ( $config->listNodes("$path qos-policy") ) {
	my $policy = $config->returnValue("$path qos-policy $dir");
	if ($policy eq $name) {
	    push @inuse, "$path $dir";
	}
    }
    return @inuse;
}

sub ether_vif_using {
    my ($config, $name, $type, $interface) = @_;
    my @affected = ();

    foreach my $vif ( $config->listNodes("$type $interface vif") ) {
	my $path = "$type $interface vif $vif";
	push @affected, using_policy($config, $name, $path);
    }
    return @affected;
}

sub adsl_vif_using {
    my ($config, $name, $type, $interface) = @_;
    my @affected = ();

    foreach my $pvc ( $config->listNodes("$type $interface pvc") ) {
	foreach my $pvctype ( $config->listNodes("$type $interface pvc $pvc") ) {
	    foreach my $vc ( $config->listNodes("$type $interface pvc $pvc $pvctype") ) {
		my $path = "$type $interface pvc $pvc $pvctype $vc";
		push @affected, using_policy($config, $name, $path);
	    }
	}
    }
    return @affected;
}

sub serial_vif_using {
    my ($config, $name, $type, $interface) = @_;
    my @affected = ();

    foreach my $encap (qw/cisco-hdlc frame-relay ppp/) {
	foreach my $vif ( $config->listNodes("$type $interface vif") ) {
	    push @affected, 
	    	using_policy($config, $name, "$type $interface $encap vif $vif");
	}
    }

    return @affected;
}


my %interfaceVifUsing = (
    'ethernet'	=> \&ether_vif_using,
    'bonding'	=> \&ether_vif_using,
    'serial'	=> \&serial_vif_using,
    'adsl'	=> \&adsl_vif_using,
);

sub interfaces_using {
    my ($name) = @_;
    my $config = new Vyatta::Config;
    my @affected = ();

    $config->setLevel('interfaces');
    foreach my $type ( $config->listNodes() ) {
	foreach my $interface ( $config->listNodes($type) ) {
	    push @affected, using_policy($config, $name, "$type $interface");
	    
	    my $vif_check = $interfaceVifUsing{$type};
	    if ($vif_check) {
		push @affected, $vif_check->($config, $name, $type, $interface);
	    }
	}
    }

    return @affected;
}

sub etherName {
    my ($eth, $vif, $id) = @_;

    if ($vif eq 'vif') {
	return "$eth.$id";
    } else {
	return $eth;
    }
}

sub serialName {
    my ($wan, $encap, $type, $id) = @_;

    if ($encap && $type eq 'vif') {
	return "$wan.$id";
    } else {
	return $wan;
    }
}

sub adslName {
    # adsl-name pvc pvc-num ppp-type id
    my ($name, undef, undef, $type, $id) = @_;
    
    if ($id) {
	return "$name.$id";
    } else {
	return $name;
    }
}

# Handle mapping of interface types to device names with vif's
# This is because of differences in config layout
my %interfaceTypes = (
    'ethernet'	=> \&etherName,
    'bonding'	=> \&etherName,
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
    my $config = new Vyatta::Config;
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
    my $config = new Vyatta::Config;

    # Syntax check
    make_policy($config, $shaper, $name);
}

sub apply_changes {
    my $config = new Vyatta::Config;

    $config->setLevel('qos-policy');
    foreach my $policy ($config->listNodes()) {
	foreach my $name ($config->listNodes($policy)) {
	    my $shaper = make_policy($config, $policy, $name);

	    if ($shaper->isChanged($name)) {
		foreach my $cfgpath (interfaces_using($name)) {
		    # ethernet ethX vif 1 out
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

sub usage {
	print <<EOF;
usage: vyatta-qos.pl --check
       vyatta-qos.pl --list-policy
       vyatta-qos.pl --apply-changes

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

GetOptions(
    "check"		    => sub { check_conflict(); },
    "apply-changes"         => sub { apply_changes(); },
    "start-interace=s"	    => sub { start_interface( $_[1] ); },
    "update-interface=s{3}" => \@updateInterface,
    "delete-interface=s{2}" => \@deleteInterface,

    "list-policy=s"         => sub { list_policy( $_[1] ); },
    "delete-policy=s"       => sub { delete_policy( $_[1] ); },
    "create-policy=s{2}"    => \@createPolicy,
) or usage();

delete_interface(@deleteInterface) if ( $#deleteInterface == 1 );
update_interface(@updateInterface) if ( $#updateInterface == 2 );
create_policy(@createPolicy)	   if ( $#createPolicy == 1);


