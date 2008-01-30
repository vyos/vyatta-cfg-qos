#!/usr/bin/perl

use lib "/opt/vyatta/share/perl5/";
use VyattaConfig;
use VyattaQosPolicy;

use Getopt::Long;

my $qosNode = 'qos-policy';

my @update = ();
my @delete = ();
my $debug = $ENV{"DEBUG"};
my $list = undef;

GetOptions(
    "debug"       => \$debug,
    "list"        => \$list,
    "update=s{3}" => \@update,
    "delete=s{2}" => \@delete,
);

## list available qos policy names
sub list_available {
    my $config = new VyattaConfig;
    my @nodes  = ();

    foreach my $policy ( $config->listNodes($qosNode) ) {
        foreach my $name ( $config->listNodes("$qosNode $policy") ) {
            push @nodes, $name;
        }
    }

    print join( ' ', @nodes ), "\n";
}

## delete_interface('eth0', 'out')
# remove all filters and qdisc's
sub delete_interface {
    my ( $interface, $direction ) = @_;

    if ( $direction =~ /^out/ ) {

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
    my ( $interface, $direction, $name ) = @_;
    my $config = new VyattaConfig;

    # TODO: add support for ingress
    ( $direction =~ /^out/ ) or die "Only out direction supported";

    foreach my $policy ( $config->listNodes($qosNode) ) {
        if ( $config->exists("$qosNode $policy $name") ) {
            $config->setLevel("$qosNode $policy $name");

            my $policy = VyattaQosPolicy->config( $config, $policy );
            defined $policy or die "undefined policy";

	    # When doing debugging just echo the commands
	    if (defined $debug) {
		open (my $out, ">&STDOUT");
	    } else {
		open( my $out, "|sudo tc -batch -" )
		    or die "Tc setup failed: $!\n";
	    }

            $policy->commands($out, $interface);
	    close $out or die "Tc command failed: $!\n";
            exit 0;
        }
    }

    die "Unknown $qosNode $name\n";
}

if ( defined $list ) {
    list_available();
    exit 0;
}

if ( $#delete == 1 ) {
    delete_interface(@delete);
    exit 0;
}

if ( $#update == 2 ) {
    update_interface(@update);
    exit 0;
}

print <<EOF;
usage: vyatta-qos.pl --list
       vyatta-qos.pl --update interface direction policy
       vyatta-qos.pl --delete interface direction
EOF
exit 1;
