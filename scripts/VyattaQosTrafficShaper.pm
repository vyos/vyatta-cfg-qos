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

        $self->{_rate}     = $config->returnValue("rate");
	defined $self->{_rate}  or die "Rate not defined for class $id\n";

	$self->{_id}	   = sprintf "%04x", $id;
        $self->{_priority} = $config->returnValue("priority");
        $self->{_ceiling}  = $config->returnValue("ceiling");
        $self->{_burst}    = $config->returnValue("burst");

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

    sub commands {
        my ( $self, $out, $dev, $speed ) = @_;
        my $rate = _getPercentRate($self->{_rate}, $speed);
	my $ceil = _getPercentRate($self->{_ceiling}, $speed);
        my $id   = $self->{_id};
	my $matches = $self->{_match};

	$rate <= $speed or 
	    die "Rate for class $id ($rate) must be less than overall rate ($speed)\n";

	# create the class
        my $cmd ="class add dev $dev parent 1:1 classid 1:$id htb rate $rate";
        if ( defined $ceil) {
	    
	    $ceil >= $rate or
		die "Rate ceiling ($ceil) must be greater than base rate ($rate)\n";
	    $cmd .= " ceil $ceil";
	}

        $cmd .= " burst $self->{_burst}"   if ( defined $self->{_burst} );
        $cmd .= " prio $self->{_priority}" if ( defined $self->{_priority} );

	print {$out} $cmd . "\n";

	# create leaf qdisc
	print {$out} "qdisc add dev $dev parent 1:$id sfq\n";

	foreach my $match (@$matches) {
	    $match->filter( $out, $dev, $id );
        }
    }
}

package VyattaQosTrafficShaper;
@ISA = qw/VyattaQosPolicy/;
use strict;
require VyattaConfig;
use VyattaQosUtil;

my $defaultId = 0x4000;

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

    $self->{_rate} = $config->returnValue("rate");

    $config->exists("default")
	or die "Configuration not complete: missing default class\n";
    $config->setLevel("$level default");
    push @classes, new ShaperClass( $config, $defaultId); 
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

    print {$out} "qdisc add dev $dev root handle 1: htb default "
    	. sprintf("%04x",$defaultId) . "\n";
    print {$out} "class add dev $dev parent 1: classid 1:1 htb rate $rate\n";

    foreach my $class (@$classes) {
        $class->commands( $out, $dev, $rate );
    }
}

1;
