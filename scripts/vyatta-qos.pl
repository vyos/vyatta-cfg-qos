#!/usr/bin/perl

use lib "/opt/vyatta/share/perl5/";
use VyattaConfig;
use VyattaQosPolicy;
use strict;

use Getopt::Long;

my $qosNode = 'qos-policy';
my $debug = $ENV{'QOS_DEBUG'};
my @updateInterface = ();
my @deleteInterface = ();
my @updatePolicy = ();
my $deletePolicy = undef;
my $listName = undef;
my $validateName = undef;

GetOptions(
    "list-policy"           => \$listName,
    "validate-name=s"       => \$validateName,
    "update-interface=s{3}" => \@updateInterface,
    "delete-interface=s{2}" => \@deleteInterface,
    "update-policy=s{2}"    => \@updatePolicy,
    "delete-policy=s"       => \$deletePolicy,
);

## list defined qos policy names
sub list_inuse {
    my $config = new VyattaConfig;
    my @nodes  = ();

    foreach my $policy ($config->listNodes($qosNode) ) {
        foreach my $name ($config->listNodes("$qosNode $policy") ) {
            push @nodes, $name;
        }
    }

    print join( ' ', @nodes ), "\n";
}

## check if name is okay
sub validate_name {
    my $name = shift;
    my $config = new VyattaConfig;

    ($name =~ '^\w[\w_-]*$') or die "Invalid policy name $name\n";

    foreach my $policy ($config->listNodes($qosNode) ) {
        foreach my $node ($config->listNodes("$qosNode $policy") ) {
	    if ($name eq $node) {
		die "Name $name is already in use by $policy\n";
	    }
	}
    }
}


## delete_interface('eth0', 'out')
# remove all filters and qdisc's
sub delete_interface {
    my ($interface, $direction ) = @_;

    if ($direction eq "out" ) {

        # delete old qdisc - will give error if no policy in place
        system("tc qdisc del dev $interface root 2>/dev/null");
        system("tc filter del dev $interface 2>/dev/null");
    }
    else {
        return -1;
    }
}

## update_interface('eth0', 'out', 'my-shaper')
# update policy to interface
sub update_interface {
    my ($interface, $direction, $name ) = @_;
    my $config = new VyattaConfig;

    print "update_interface $interface $direction $name\n";
    # TODO: add support for ingress
    ( $direction eq "out" ) or die "Only out direction supported";

    foreach my $policy ( $config->listNodes($qosNode) ) {
        if ( $config->exists("$qosNode $policy $name") ) {
            $config->setLevel("$qosNode $policy $name");

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
		die "Tc commands failed\n";
	    }
            exit 0;
        }
    }

    die "Unknown $qosNode $name\n";
}

sub delete_policy {
    my ( $name ) = @_;
    my $config = new VyattaConfig;

    $config->setLevel("interfaces ethernet");
    foreach my $interface ( $config->listNodes() ) {
	foreach my $direction ($config->listNodes("$interface qos-policy")) {
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
    foreach my $interface ( $config->listNodes()) {
	foreach my $direction ($config->listNodes("$interface qos-policy")) {
	    if ($config->returnValue("$interface qos-policy $direction") eq $name) {
		delete_interface($interface, $direction);
		update_interface($interface, $direction, $name);
	    }
	}
    }
}

if ( defined $listName ) {
    list_inuse();
    exit 0;
}

if ( defined $validateName ) {
    validate_name($validateName);
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

if ( defined $deletePolicy ) {
    delete_policy($deletePolicy);
    exit 0;
}

if ( $#updatePolicy == 1) {
    update_policy(@updatePolicy);
    exit 0;
}

print <<EOF;
usage: vyatta-qos.pl --list-policy
       vyatta-qos.pl --validate-name policy-name
       vyatta-qos.pl --update-interface interface direction policy-name
       vyatta-qos.pl --delete-interface interface direction
       vyatta-qos.pl --update-policy policy-type policy-name
       vyatta-qos.pl --delete-policy policy-type policy-name
EOF
exit 1;
