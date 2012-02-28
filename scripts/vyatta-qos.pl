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
	'shaper'           => 'TrafficShaper',
	'fair-queue'       => 'FairQueue',
	'rate-control'     => 'RateLimiter',
	'drop-tail'        => 'DropTail',
	'network-emulator' => 'NetworkEmulator',
	'round-robin'      => 'RoundRobin',
	'priority-queue'   => 'Priority',
	'random-detect'    => 'RandomDetect',
    },
    'in' => {
	'limiter' => 'TrafficLimiter',
    }
);

# find policy for name - also check for duplicates
## find_policy('limited')
sub find_policy {
    my $name   = shift;
    my $config = new Vyatta::Config;

    $config->setLevel('traffic-policy');
    my @policy = grep { $config->exists("$_ $name") } $config->listNodes();

    die "Policy name \"$name\" conflict, used by: ", join( ' ', @policy ), "\n"
      if ( $#policy > 0 );

    return $policy[0];
}

# class factory for policies
sub make_policy {
    my ( $type, $name, $direction ) = @_;
    my $policy_type;

    if ($direction) {
        $policy_type = $policies{$direction}{$type};
    } else {
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
    $config->setLevel("traffic-policy $type $name");

    my $location = "Vyatta/Qos/$policy_type.pm";
    my $class    = "Vyatta::Qos::$policy_type";

    require $location;

    return $class->new( $config, $name, $direction );
}

## list defined qos policy names
sub list_policy {
    my $config = new Vyatta::Config;
    $config->setLevel('traffic-policy');

    while ( my $direction = shift ) {
        my @qos = grep { $policies{$direction}{$_} } $config->listNodes();
        my @names = ();
        foreach my $type (@qos) {
            my @n = $config->listNodes($type);
            push @names, @n;
        }
        print join( ' ', @names ), "\n";
    }
}

my %delcmd = (
    'out' => 'root',
    'in'  => 'parent ffff:',
);

## delete_interface('eth0')
# remove all filters and qdisc's
sub delete_interface {
    my ( $interface, $direction ) = @_;
    my $arg = $delcmd{$direction};

    die "bad direction $direction\n" unless $arg;

    my $cmd = "/sbin/tc qdisc del dev $interface ". $arg . " 2>/dev/null";

    # ignore errors (may have no qdisc)
    system($cmd);
}

## start_interface('ppp0')
# reapply qos policy to interface
sub start_interface {
    while ( my $ifname = shift ) {
        my $interface = new Vyatta::Interface($ifname);
        die "Unknown interface type: $ifname" unless $interface;

	my $path = $interface->path();
	next unless $path;

        my $config = new Vyatta::Config;
	$config->setLevel($path . ' traffic-policy');

        foreach my $direction ($config->listNodes()) {
	    my $policy = $config->returnValue($direction);
	    next unless $policy;

	    update_interface( $ifname, $direction, $policy );
	}
    }
}

sub start_openvpn_interface {
  my ($ifname, $direction, $policy) = @_;
  update_interface( $ifname, $direction, $policy );
}
sub apply_openvpn_action {
  my ($dev, $action, $target) = @_;
  my $interface = new Vyatta::Interface($dev);
  die "Unknown interface type: $dev" unless $interface;

	# Clear existing ingress
	system("/sbin/tc qdisc del dev $dev parent ffff: 2>/dev/null");

	system("/sbin/tc qdisc add dev $dev handle ffff: ingress") == 0
	    or die "tc qdisc ingress failed";

	my $cmd =
	    "/sbin/tc filter add dev $dev parent ffff:"
	    . " protocol all prio 10 u32"
	    . " match u32 0 0 flowid 1:1"
	    . " action mirred egress $action dev $target";

	system($cmd) == 0
	    or die "tc action $action command failed";

  system("/sbin/tc qdisc del dev $dev parent ffff: 2>/dev/null")
  	if ($action eq '__undef');
}

## interface_exists('wan0.1')
# check if interface exists
# Note: retry to handle chicken-egg problem with ppp devices
#       ppp devices can take a while to get named correctly
#       ppp script won't see policy until it is committed
sub interface_exists {
    my $ifname = shift;
    my $sysfs  = "/sys/class/net/$ifname";

    for (my $i = 0; $i < 10; ++$i) {
	return 1 if ( -d $sysfs );
	sleep 1;
    }
    return;
}

## update_interface('eth0', 'my-shaper')
# update policy to interface
sub update_interface {
    my ( $device, $direction, $name ) = @_;
    my $policy = find_policy($name);
    die "Unknown traffic-policy $name\n" unless $policy;

    my $shaper = make_policy( $policy, $name, $direction );
    exit 1 unless $shaper;

    unless (interface_exists($device)) {
	warn "$device not present yet, traffic-policy will be applied later\n";
	return;
    }

    # Remove old policy
    delete_interface( $device, $direction );

    # When doing debugging just echo the commands
    my $out;
    unless ($debug) {
        open ( $out, '|-', '/sbin/tc -batch -' )
	    or die "Tc setup failed: $!\n";

	select $out;
    }

    $shaper->commands( $device, $direction );

    return if ($debug);

    select STDOUT;

    unless(close($out)) {
        # cleanup any partial commands
        delete_interface( $device, $direction );

        # replay commands to stdout
        $shaper->commands($device, $direction );
        die "TC command failed.";
    }
}

# return array of references to (name, direction, policy)
sub interfaces_using {
    my $policy = shift;
    my $config = new Vyatta::Config;
    my @inuse  = ();

    foreach my $name ( getInterfaces() ) {
        my $intf = new Vyatta::Interface($name);
        next unless $intf;
	my $level = $intf->path() . ' traffic-policy';
	$config->setLevel($level);

        foreach my $direction ($config->listNodes()) {
	    my $cur = $config->returnValue($direction);
	    next unless $cur;

	    # these are arguments to update_interface()
	    push @inuse, [ $name, $direction, $policy ]
		if ($cur eq $policy);
	}
    }
    return @inuse;
}

# check if policy name(s) are still in use
sub delete_policy {
    while ( my $name = shift ) {
	# interfaces_using returns array of array and only want name
	my @inuse = map { @$_[0] } interfaces_using($name);

	die "Can not delete traffic-policy $name, still applied"
	    . " to interface ", join(', ', @inuse), "\n"
	    if @inuse;
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
    while (my $name = shift) {
	my @usedby = interfaces_using($name);
	if (@usedby) {
	    foreach my $args (@usedby) {
		update_interface( @$args );
	    }
	} elsif (my $policy = find_policy($name)) {
	    # Recheck the policy, might have new errors.
	    my $shaper = make_policy( $policy, $name );
	    exit 1 unless $shaper;
	}
    }
}

#
# This is used for actions mirror and redirect
sub update_action {
    while ( my $dev = shift ) {
	apply_action($dev);
    }
}

sub apply_action{
    my $dev = shift;
    my $interface = new Vyatta::Interface($dev);
    die "Unknown interface type: $dev" unless $interface;

    my $path = $interface->path();
    next unless $path;

    my $config = new Vyatta::Config;
    $config->setLevel( $path );

    my $ingress =  $config->returnValue('traffic-policy in');

    foreach my $action (qw(mirror redirect)) {
	my $target = $config->returnValue($action);
	next unless $target;

	# TODO support combination of limiting and redirect/mirror
	die "interface $dev: combination of $action"
	    . " and traffic-policy $ingress not supported\n"
	    if ($ingress);

	# Clear existing ingress
	system("/sbin/tc qdisc del dev $dev parent ffff: 2>/dev/null");

	system("/sbin/tc qdisc add dev $dev handle ffff: ingress") == 0
	    or die "tc qdisc ingress failed";

	my $cmd =
	    "/sbin/tc filter add dev $dev parent ffff:"
	    . " protocol all prio 10 u32"
	    . " match u32 0 0 flowid 1:1"
	    . " action mirred egress $action dev $target";

	system($cmd) == 0
	    or die "tc action $action command failed";

	return;
    }

    # Drop what ever was there before...
    system("/sbin/tc qdisc del dev $dev parent ffff: 2>/dev/null")
	unless($ingress);
}

# find any interfaces whose actions refer to this interface
sub interfaces_refer {
    my $dev = shift;
    my $config = new Vyatta::Config;
    my @inuse  = ();

    foreach my $name ( getInterfaces() ) {
        my $intf = new Vyatta::Interface($name);
        next unless $intf;
	$config->setLevel($intf->path());

	foreach my $policy ( qw(redirect mirror) ) {
	    my $target = $config->returnValue($policy);
	    next unless $target;

	    if ($dev eq $target) {
		push @inuse, $name;
		last;
	    }
	}
    }

    return @inuse;
}

sub check_target {
    my $name= shift;
    my @inuse = interfaces_refer ( $name );

    die "Can not delete interface $name, still being used by: ",
       join(', ', @inuse), "\n" if @inuse;

}

sub delete_action {
    foreach my $dev (@_) {
	system("/sbin/tc qdisc del dev $dev parent ffff: 2>/dev/null");
    }
}

sub usage {
    print <<EOF;
usage: vyatta-qos.pl --list-policy direction
       vyatta-qos.pl --create-policy policy-type policy-name
       vyatta-qos.pl --delete-policy policy-name
       vyatta-qos.pl --apply-policy policy-type policy-name

       vyatta-qos.pl --update-interface interface direction policy-name
       vyatta-qos.pl --delete-interface interface direction
       vyatta-qos.pl --start-interface interface

       vyatta-qos.pl --update-action interface
       vyatta-qos.pl --delete-action interface
EOF
    exit 1;
}

my (@startList, @updateInterface, @deleteInterface);
my ($updateAction, $deleteAction, $checkTarget);
my ($listPolicy, @createPolicy, @applyPolicy, @deletePolicy);
my (@startOpenVPNList, @openvpnAction);

GetOptions(
    "start-interface=s"     => \@startList,
    "start-openvpn-interface=s{3}"=> \@startOpenVPNList,
    "update-openvpn-action=s{3}"=> \@openvpnAction,
    "update-interface=s{3}" => \@updateInterface,
    "delete-interface=s{2}" => \@deleteInterface,

    "list-policy=s"         => \$listPolicy,
    "delete-policy=s"       => \@deletePolicy,
    "create-policy=s{2}"    => \@createPolicy,
    "apply-policy=s"        => \@applyPolicy,

    "update-action=s"	    => \$updateAction,
    "delete-action=s"	    => \$deleteAction,
    "check-target=s"	    => \$checkTarget,
) or usage();

delete_interface(@deleteInterface) if ( $#deleteInterface == 1 );
update_interface(@updateInterface) if ( $#updateInterface == 2 );
start_interface(@startList)        if ( @startList );
start_openvpn_interface(@startOpenVPNList)        if ( @startOpenVPNList );
apply_openvpn_action(@openvpnAction)	   if ( @openvpnAction );

list_policy($listPolicy)           if ( $listPolicy );
create_policy(@createPolicy)       if ( $#createPolicy == 1 );
delete_policy(@deletePolicy)       if ( @deletePolicy );
apply_policy(@applyPolicy)         if ( @applyPolicy );

update_action($updateAction)	   if ( $updateAction );
delete_action($deleteAction)	   if ( $deleteAction );
check_target($checkTarget)	   if ( $checkTarget );
