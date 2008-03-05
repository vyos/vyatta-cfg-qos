#!/usr/bin/perl

use lib "/opt/vyatta/share/perl5/";
use VyattaConfig;
use VyattaQosPolicy;
use strict;

use Getopt::Long;

my $debug = $ENV{'QOS_DEBUG'};
my @updateInterface = ();
my @deleteInterface = ();
my @updatePolicy = ();
my @deletePolicy = ();
my $listPolicy = undef;

GetOptions(
    "update-interface=s{3}" => \@updateInterface,
    "delete-interface=s{2}" => \@deleteInterface,

    "list-policy"           => \$listPolicy,
    "update-policy=s{2}"    => \@updatePolicy,
    "delete-policy=s{2}"    => \@deletePolicy,
);

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
	qx(sudo tc qdisc del dev "$interface" root 2>/dev/null);
    }
}

## update_interface('eth0', 'out', 'my-shaper')
# update policy to interface
sub update_interface {
    my ($interface, $direction, $name ) = @_;
    my $config = new VyattaConfig;

    ( $direction eq "out" ) or die "Only out direction supported";

    $config->setLevel('qos-policy');
    foreach my $policy ( $config->listNodes() ) {
        if ( $config->exists("$policy $name") ) {
            $config->setLevel("qos-policy $policy $name");

            my $policy = VyattaQosPolicy->config( $config, $policy );
            defined $policy or die "undefined policy";

	    # When doing debugging just echo the commands
	    my $out;
	    if (defined $debug) {
		open $out, '>-'
		    or die "can't open stdout: $!";
	    } else {
		open $out, "|-" or exec qw/sudo tc -batch -/
		    or die "Tc setup failed: $!\n";
	    }

            $policy->commands($out, $interface);
	    if (! close $out && ! defined $debug) {
		delete_interface($interface, $direction);

		# replay commands to stdout
		open $out, '>-';
		$policy->commands($out, $interface);
		close $out;
		die "Conversion of configuration to tc command error\n";
	    }
            exit 0;
        }
    }

    die "Unknown qos-policy $name\n";
}

sub delete_policy {
    my ($shaper, $name) = @_;
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

sub update_policy {
    my ($shaper, $name) = @_;
    my $config = new VyattaConfig;

    $config->setLevel("interfaces ethernet");
    foreach my $interface ( $config->listNodes() ) {
	foreach my $direction ( $config->listNodes("$interface qos-policy") ) {
	    if ($config->returnValue("$interface qos-policy $direction") eq $name) {
		delete_interface($interface, $direction);
		update_interface($interface, $direction, $name);
	    }
	}
    }
}

if ( $listPolicy ) {
    list_policy();
    exit 0;
}


if ( @deleteInterface ) {
    delete_interface(@deleteInterface);
    exit 0;
}

if ( @updateInterface ) {
    update_interface(@updateInterface);
    exit 0;
}

if ( @deletePolicy ) {
    delete_policy(@deletePolicy);
    exit 0;
}

if ( @updatePolicy ) {
    update_policy(@updatePolicy);
    exit 0;
}

print <<EOF;
usage: vyatta-qos.pl --list-policy
       vyatta-qos.pl --update-interface interface direction policy-name
       vyatta-qos.pl --delete-interface interface direction
       vyatta-qos.pl --update-policy policy-type policy-name
       vyatta-qos.pl --delete-policy policy-type policy-name
EOF
exit 1;
