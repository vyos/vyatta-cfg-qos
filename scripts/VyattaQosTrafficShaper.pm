# Traffic shaper
# This is a extended form of Hierarchal Token Bucket with
# more admin friendly features. Similar in spirt to other shaper scripts
# such as wondershaper.

{
    package ShaperClass;
    use strict;
    require VyattaConfig;
    use VyattaQosMatch;

    my %fields = (
	id	  => undef,
	dsmark	  => undef,
        _priority => undef,
        _rate     => undef,
        _ceiling  => undef,
        _burst    => undef,
        _match    => undef,
    );

    sub new {
        my ( $that, $config, $id ) = @_;
        my $class = ref($that) || $that;
        my $self = {%fields};

        bless $self, $class;
        $self->_define($config, $id);

        return $self;
    }

    sub _define {
        my ( $self, $config, $id ) = @_;
	my $level = $config->setLevel();
	my @matches = ();

        $self->{_rate}     = $config->returnValue("bandwidth");
	defined $self->{_rate}  or die "Bandwidth not defined for class $id\n";

	$self->{id}	   = $id;
        $self->{_priority} = $config->returnValue("priority");
        $self->{_ceiling}  = $config->returnValue("ceiling");
        $self->{_burst}    = $config->returnValue("burst");
        $self->{dsmark} = VyattaQosUtil::getDsfield($config->returnValue("set-dscp"));

	foreach my $match ($config->listNodes("match")) {
            $config->setLevel("$level match $match");
	    push @matches, new VyattaQosMatch($config);
        }
	$self->{_match}    = \@matches;
    }

    sub _getPercentRate {
	my ($rate, $speed) = @_;

        if ( ! defined $rate ) {
	    return;  # leave rate undef
	}

        # Rate might be a percentage of speed
        if ( $rate =~ /%$/ ) {
            my $percent = substr( $rate, 0, length($rate) - 1 );
            if ( $percent < 0 || $percent > 100 ) {
                die "Invalid percentage bandwidth: $percent\n";
            }

            $rate = ( $percent * $speed ) / 100.;
        } else {
	    $rate = VyattaQosUtil::getRate($rate);
	}

	return $rate;
    }

    sub rateCheck {
	my ($self, $speed) = @_;
        my $rate = _getPercentRate($self->{_rate}, $speed);
	my $ceil = _getPercentRate($self->{_ceiling}, $speed);

	if ($rate > $speed) {
	    die "Bandwidth for class $self->{id} ($rate) > overall limit ($speed)\n";
	}

	# create the class
        if (defined $ceil && $ceil < $rate) {
	    die "Ceiling ($ceil) must be greater than bandwith ($rate)\n";
	}
    }

    sub htbClass {
        my ( $self, $out, $parent, $dev, $speed ) = @_;
        my $rate = _getPercentRate($self->{_rate}, $speed);
	my $ceil = _getPercentRate($self->{_ceiling}, $speed);
	my $id = sprintf "%04x", $self->{id};
	print ${out} "class add dev $dev parent $parent:1 classid 1:$id htb rate $rate";

	print ${out} " burst $self->{_burst}"   if ( defined $self->{_burst} );
	print ${out} " prio $self->{_priority}" if ( defined $self->{_priority} );
	print {$out} "\n";

	# create leaf qdisc
	print {$out} "qdisc add dev $dev parent $parent:$id sfq\n";

	my $matches = $self->{_match};
	foreach my $match (@$matches) {
	    $match->filter( $out, $dev, $id );
        }
    }

    sub dsmarkClass {
	my ( $self, $out, $parent, $dev ) = @_;
	my $id = sprintf "%x", $self->{id};

	print ${out} "class change dev $dev classid $parent:$id dsmark";
	if ($self->{dsmark}) {
	    print ${out} " mask 0 value $self->{dsmark}\n";
	} else {
	    print ${out} " mask 0xff value 0\n";
	}
    }

}

package VyattaQosTrafficShaper;
@ISA = qw/VyattaQosPolicy/;
use strict;
require VyattaConfig;
use VyattaQosUtil;

my %fields = (
    _rate       => undef,
    _classes    => undef,
);

# new VyattaQosTrafficShaper($config)
# Create a new instance based on config information
sub new {
    my ( $that, $config ) = @_;
    my $self = {%fields};
    my $class = ref($that) || $that;

    bless $self, $class;
    $self->_define($config);

    return $self;
}

# Rate can be something like "auto" or "10.2mbit"
sub _getAutoRate {
    my ($rate, $dev) = @_;

    if ( $rate eq "auto" ) {
        $rate = VyattaQosUtil::interfaceRate($dev);
        if ( ! defined $rate ) {
	    die "Interface speed defined as auto but can't get rate from $dev\n";
	}
    } else {
	$rate = VyattaQosUtil::getRate($rate);
    }

    return $rate;
}

# Setup new instance.
# Assumes caller has done $config->setLevel to "traffic-shaper $name"
sub _define {
    my ( $self, $config ) = @_;
    my $level = $config->setLevel();
    my @classes = ( );

    $self->{_rate} = $config->returnValue("bandwidth");

    $config->exists("default")
	or die "Configuration not complete: missing default class\n";

    # make sure no clash of different types of tc filters
    my %matchTypes = ();
    foreach my $class ( $config->listNodes("class")) {
	foreach my $match ( $config->listNodes("class $class match") ) {
	    foreach my $type ( $config->listNodes("class $class match $match") ) {
		$matchTypes{$type} = "$class match $match";
	    }
	}
    }

    if (scalar keys %matchTypes > 1 && $matchTypes{ip}) {
	print "Match type conflict:\n";
	while (my ($type, $usage) = each(%matchTypes)) {
	    print "   class $usage $type\n";
	}
	die "Can't match on both ip and other types\n";
    }


    $config->setLevel("$level default");
    push @classes, new ShaperClass($config, -1);
    $config->setLevel($level);

    foreach my $id ( $config->listNodes("class") ) {
        $config->setLevel("$level class $id");
	push @classes, new ShaperClass( $config, $id );
    }
    $self->{_classes} = \@classes;
}

sub commands {
    my ( $self, $out, $dev ) = @_;
    my $rate = _getAutoRate($self->{_rate}, $dev);
    my $classes = $self->{_classes};
    my %dsmark = ();

    my $maxid = 1;
    foreach my $class (@$classes) {
	# rate constraints
	$class->rateCheck($rate);

	# find largest class id
	if (defined $class->{id} && $class->{id} > $maxid) {
	    $maxid = $class->{id};
	}
    }

    # fill in id of default
    my $default = shift @$classes;
    $default->{id} = ++$maxid;
    unshift @$classes, $default;

    # if any dscp marking, then set up hash
    my $usedsmark;
    foreach my $class (@$classes) {
	if (defined $class->{dsmark}) {
	    print "Class $class->{id} uses dsmark\n";
	    $usedsmark = 1;
	    last;
	}
    }

    my $parent = "1";
    my $root = "root";
    if ($usedsmark) {
	print {$out} "qdisc add dev $dev root handle 1: dsmark "
	    . " indicies $maxid+1 default_index $default->{id}\n";
	foreach my $class (@$classes) {
	    $class->dsmarkClass($out, "1", $dev);
	}
	$parent = "4000";
	$root = "parent 1:1"
    }

    print {$out} "qdisc add dev $dev $root handle $parent: htb";
    printf {$out} " default %x\n", $default->{id};
    print {$out} "class add dev $dev parent 1: classid $parent:1 htb rate $rate\n";

    foreach my $class (@$classes) {
        $class->htbClass($out, $parent, $dev, $rate);
    }
}

1;
