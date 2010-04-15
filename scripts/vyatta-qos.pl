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
    'traffic-shaper'   => 'TrafficShaper',
    'fair-queue'       => 'FairQueue',
    'rate-control'     => 'RateLimiter',
    'drop-tail'        => 'DropTail',
    'network-emulator' => 'NetworkEmulator',
    'round-robin'      => 'RoundRobin',
    'priority-queue'   => 'Priority',
    'random-detect'    => 'RandomDetect',
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
    my ( $type, $name ) = @_;
    my $policy_type;

    $policy_type = $policies{$type};

    # This means template exists but we don't know what it is.
    return unless ($policy_type);

    my $config = new Vyatta::Config;
    $config->setLevel("qos-policy $type $name");

    my $location = "Vyatta/Qos/$policy_type.pm";
    my $class    = "Vyatta::Qos::$policy_type";

    require $location;

    return $class->new( $config, $name );
}

## list defined qos policy names
sub list_policy {
    my $config = new Vyatta::Config;
    $config->setLevel('qos-policy');

    # list all nodes under qos-policy and match those we know about
    my @qos = grep { $policies{$_} } $config->listNodes();

    my @names = ();
    foreach my $type (@qos) {
            my @n = $config->listNodes($type);
            push @names, @n;
    }
    print join( ' ', sort ( @names )), "\n";
}

## delete_interface('eth0')
# remove all filters and qdisc's
sub delete_interface {
    my ( $interface ) = @_;

    system("sudo tc qdisc del dev $interface root 2>/dev/null");
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
        $config->setLevel( $path );
	my $policy = $config->returnValue('qos-policy');
	next unless $policy;

	update_interface( $ifname, $policy );
    }
}

## update_interface('eth0', 'my-shaper')
# update policy to interface
sub update_interface {
    my ( $device, $name ) = @_;
    my $policy = find_policy($name);
    die "Unknown qos-policy $name\n" unless $policy;

    my $shaper = make_policy( $policy, $name );
    exit 1 unless $shaper;

    if ( ! -d "/sys/class/net/$device" ) {
	warn "$device not present yet, qos-policy will be applied later\n";
	return;
    }

    # Remove old policy
    delete_interface( $device );

    # When doing debugging just echo the commands
    my $out;
    unless ($debug) {
        open $out, "|-"
          or exec qw:sudo /sbin/tc -batch -:
          or die "Tc setup failed: $!\n";

	select $out;
    }

    my $parent = 1;
    $shaper->commands( $device, $parent );
    return if ($debug);

    select STDOUT;
    unless (close $out) {
        # cleanup any partial commands
        delete_interface( $device );

        # replay commands to stdout
        $shaper->commands($device, $parent );
        die "TC command failed.";
    }
}


# return array of references to (name, policy)
sub interfaces_using {
    my $policy = shift;
    my $config = new Vyatta::Config;
    my @inuse  = ();

    foreach my $name ( getInterfaces() ) {
        my $intf = new Vyatta::Interface($name);
        next unless $intf;
	my $path = $intf->path();
	next unless $path;

	$config->setLevel($path);
	my $cur = $config->returnValue('qos-policy');
	next unless $cur;

	# these are arguments to update_interface()
	push @inuse, [ $name, $policy ] if ($cur eq $policy);
    }
    return @inuse;
}

# check if policy name(s) are still in use
sub delete_policy {
    while ( my $name = shift ) {
	# interfaces_using returns array of array and only want name
	my @inuse = map { @$_[0] } interfaces_using($name);

	die "Can not delete qos-policy $name, still applied"
	    . " to interface ", join(' ', @inuse), "\n"
	    if @inuse;
    }
}

sub create_policy {
    my ( $policy, $name ) = @_;
    find_policy($name);

    # Check policy for validity
    my $shaper = make_policy( $policy, $name );
    die "QoS policy $name has not been created\n" unless $shaper;
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

# ingress policy factory
sub ingress_policy {
    my ($ifname) = @_;
    my $intf = new Vyatta::Interface($ifname);
    die "Unknown interface name $ifname\n" unless $intf;

    my $path = $intf->path();
    unless ($path) {
	warn "Can't find $ifname in configuration\n";
	exit 0;
    }

    my $config = new Vyatta::Config;
    $config->setLevel( "$path input-policy" );

    my @names = $config->listNodes();
    return if ($#names < 0);

    die "Only one incoming policy is allowed\n" if ($#names > 0);

    $config->setLevel( "$path input-policy " . $names[0] );
    my $type     = ucfirst($names[0]);
    my $location = "Vyatta/Qos/Ingress$type.pm";
    require $location;

    my $class    = "Vyatta::Qos::Ingress$type";
    return $class->new( $config, $ifname );
}

# check definition of input filtering
sub check_ingress {
    my $device = shift;

    my $ingress = ingress_policy( $device );
    return unless $ingress;
}

# sets up input filtering
sub update_ingress {
    my $device = shift;

    die "Interface $device not present\n"
	unless (-d "/sys/class/net/$device");

    # Drop existing ingress and recreate
    system("sudo tc qdisc del dev $device ingress 2>/dev/null");

   my $ingress = ingress_policy( $device );
    return unless $ingress;

    system("sudo tc qdisc add dev $device ingress") == 0
	or die "Can not set ingress qdisc";

    # When doing debugging just echo the commands
    my $out;
    unless ($debug) {
        open $out, "|-"
          or exec qw:sudo /sbin/tc -batch -:
          or die "Tc setup failed: $!\n";

	select $out;
    }

    my $parent = 0xffff;
    $ingress->commands( $device, $parent );
    return if ($debug);

    select STDOUT;
    unless (close $out) {
        # cleanup any partial commands
	system("sudo tc del dev $device ingress 2>/dev/null");

        # replay commands to stdout
        $ingress->commands($device, $parent );
        die "TC command failed.";
    }
}

sub usage {
    print <<EOF;
usage: vyatta-qos.pl --list-policy
       vyatta-qos.pl --create-policy policy-type policy-name
       vyatta-qos.pl --delete-policy policy-name
       vyatta-qos.pl --apply-policy policy-type policy-name

       vyatta-qos.pl --update-interface interface policy-name
       vyatta-qos.pl --delete-interface interface

       vyatta-qos.pl --check-ingress interface
       vyatta-qos.pl --update-ingress interface
EOF
    exit 1;
}

my @updateInterface = ();
my $deleteInterface;

my $listPolicy;
my @createPolicy    = ();
my @applyPolicy     = ();
my @deletePolicy    = ();
my @startList       = ();

my ($checkIngress, $updateIngress);

GetOptions(
    "start-interface=s"     => \@startList,
    "update-interface=s{2}" => \@updateInterface,
    "delete-interface=s"    => \$deleteInterface,

    "list-policy"           => \$listPolicy,
    "delete-policy=s"       => \@deletePolicy,
    "create-policy=s{2}"    => \@createPolicy,
    "apply-policy=s"        => \@applyPolicy,

    "check-ingress=s"	    => \$checkIngress,
    "update-ingress=s"	    => \$updateIngress
) or usage();

delete_interface($deleteInterface) if ( $deleteInterface );
update_interface(@updateInterface) if ( $#updateInterface == 1 );
start_interface(@startList)        if (@startList);

list_policy()                      if ( $listPolicy );
create_policy(@createPolicy)       if ( $#createPolicy == 1 );
delete_policy(@deletePolicy)       if (@deletePolicy);
apply_policy(@applyPolicy)         if (@applyPolicy);

check_ingress($checkIngress)	   if ($checkIngress);
update_ingress($updateIngress)	   if ($updateIngress);

