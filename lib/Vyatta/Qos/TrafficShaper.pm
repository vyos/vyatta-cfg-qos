# Traffic shaper
# This is a extended form of Hierarchal Token Bucket with
# more admin friendly features. Similar in spirt to other shaper scripts
# such as wondershaper.
#
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

{
    package ShaperClass;
    use strict;
    require Vyatta::Config;
    use Vyatta::Qos::Match;
    use Vyatta::Qos::Util qw/getDsfield getRate/;

    my %fields = (
	id	  => undef,
	dsmark	  => undef,
        _priority => undef,
        _rate     => undef,
        _ceiling  => undef,
        _burst    => undef,
        _match    => undef,
	_limit	  => undef,
	_qdisc    => undef,
    );

    sub new {
        my ( $that, $config, $id ) = @_;
        my $class = ref($that) || $that;
        my $self = {%fields};

	$self->{id}	   = $id;

        bless $self, $class;
        $self->_define($config);

        return $self;
    }

    sub _define {
        my ( $self, $config ) = @_;
	my $level = $config->setLevel();
	my @matches = ();

        $self->{_rate}     = $config->returnValue("bandwidth");
	defined $self->{_rate}  or die "$level bandwidth not defined\n";

        $self->{_priority} = $config->returnValue("priority");
        $self->{_ceiling}  = $config->returnValue("ceiling");
        $self->{_burst}    = $config->returnValue("burst");
	$self->{_limit}	   = $config->returnValue("queue-limit");
	$self->{_qdisc}    = $config->returnValue("queue-type");

        $self->{dsmark} = getDsfield($config->returnValue("set-dscp"));

	foreach my $match ($config->listNodes("match")) {
            $config->setLevel("$level match $match");
	    push @matches, new Vyatta::Qos::Match($config);
        }
	$self->{_match}    = \@matches;
    }

    sub matchRules {
	my ($self) = @_;
	my $matches = $self->{_match};
	return @$matches;
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
	    $rate = getRate($rate);
	}

	return $rate;
    }

    sub rateCheck {
	my ($self, $limit, $level) = @_;

        my $rate = _getPercentRate($self->{_rate}, $limit);
	if ($rate > $limit) {
	    print STDERR "Configuration error in: $level\n";
	    printf STDERR 
		"The bandwidth reserved for this class (%dKbps) must be less than\n",
	    	$rate / 1000;
	    printf STDERR "the bandwidth for the overall policy (%dKbps)\n",
	        $limit / 1000;
	    exit 1;
	}

	my $ceil = _getPercentRate($self->{_ceiling}, $limit);
        if (defined $ceil && $ceil < $rate) {
	    print STDERR "Configuration error in: $level\n";
	    printf STDERR 
		"The bandwidth ceiling for this class (%dKbps) must be greater or equal to\n",
	    	$ceil / 1000;
	    printf STDERR "the reserved bandwidth for the class (%dKbps)\n",
	        $rate / 1000;
	    exit 1;
	}
    }

    sub prioQdisc {
	my ($self, $out, $dev, $rate) = @_;
	my $prio_id = 0x4000 + $self->{id};
	my $limit = $self->{_limit};

	printf {$out} "handle %x: prio\n", $prio_id;

	if ($limit) {
	    foreach my $i (qw/1 2 3/) {
		printf {$out} "qdisc add dev %s parent %x:%d pfifo limit %d\n",
		    $dev, $prio_id, $i, $limit;
	    }
	}
    }
    
    sub sfqQdisc {
	my ($self, $out, $dev, $rate ) = @_;

	print ${out} "sfq";
	print ${out} " limit $self->{_limit}" if ($self->{_limit});
	print ${out} "\n";
    }

    sub fifoQdisc {
	my ($self, $out, $dev, $rate) = @_;

	print ${out} "pfifo";
	print ${out} " limit $self->{_limit}" if ($self->{_limit});
	print ${out} "\n";
    }

    # Red is has way to many configuration options 
    # make some assumptions to make this sane (based on LARTC)
    #   average size := 1000 bytes
    #   limit        := queue-limit * average
    #   max          := limit / 8
    #   min          := max / 3
    #   burst        := (2 * min + max) / (3 * average)
    sub redQdisc {
	my ($self, $out, $dev, $rate) = @_;
	my $limit = $self->{_limit};
	my $avg = 1000;
	my $qlimit;

	if (defined $limit) {
	    $qlimit = $limit * $avg;	# red limit in bytes
	} else {
	    # rate is in bits/sec so queue-limit = 8 * 500ms * rate
	    $qlimit = $rate / 2;
	} 
	my $qmax = $qlimit / 8;
	my $qmin = $qmax / 3;

 	printf  ${out} "red limit %d min %d max %d avpkt %d",
		$qlimit, $qmin, $qmax, $avg;
	printf ${out} " burst %d probability 0.02 bandwidth %d ecn\n",
		(2 * $qmin + $qmax) / (3 * $avg), $rate / 1000;
    }

    my %qdiscOptions = (
	'priority'	=> \&prioQdisc,
	'fair-queue'	=> \&sfqQdisc,
	'random-detect'	=> \&redQdisc,
	'drop-tail'	=> \&fifoQdisc,
	);

    sub htbClass {
        my ( $self, $out, $dev, $parent, $speed ) = @_;
        my $rate = _getPercentRate($self->{_rate}, $speed);
	my $ceil = _getPercentRate($self->{_ceiling}, $speed);

	printf ${out} "class add dev %s parent %x:1 classid %x:%x htb rate %s",
	    $dev, $parent, $parent, $self->{id}, $rate;

	print ${out} " ceil $ceil"  if ( $ceil );
	print ${out} " burst $self->{_burst}"   if ( defined $self->{_burst} );
	print ${out} " prio $self->{_priority}" if ( defined $self->{_priority} );
	print {$out} "\n";

	# create leaf qdisc
	my $q = $qdiscOptions{$self->{_qdisc}};
	if (defined $q) {
	    printf {$out} "qdisc add dev %s parent %x:%x ", 
	    	$dev, $parent, $self->{id};
	    $q->($self, $out, $dev, $rate);
	} else {
	    die "Unknown queue type $self->{_qdisc}\n";
        }
    }

    sub dsmarkClass {
	my ( $self, $out, $parent, $dev ) = @_;

	printf ${out} "class change dev %s classid %x:%x dsmark", 
		$dev, $parent, $self->{id};

	if ($self->{dsmark}) {
	    print ${out} " mask 0 value $self->{dsmark}\n";
	} else {
	    print ${out} " mask 0xff value 0\n";
	}
    }

}

package Vyatta::Qos::TrafficShaper;
use strict;

require Vyatta::Config;
use Vyatta::Qos::Util qw/getRate interfaceRate/;


my %fields = (
    _level	=> undef,
    _rate       => undef,
    _classes    => undef,
);

# Create a new instance based on config information
sub new {
    my ( $that, $config, $name ) = @_;
    my $self = {%fields};
    my $class = ref($that) || $that;

    bless $self, $class;
    $self->_define($config);

    $self->_validate($config);

    return $self;
}

sub _validate {
    my $self = shift;

    if ( $self->{_rate} ne "auto" ) {
	my $classes = $self->{_classes};
	my $default = shift @$classes;
	my $rate = getRate($self->{_rate});

	$default->rateCheck($rate, "$self->{_level} default");

	foreach my $class (@$classes) {
	    $class->rateCheck($rate, "$self->{_level} class $class->{id}");
	}
	unshift @$classes, $default
    }
}

# Rate can be something like "auto" or "10.2mbit"
sub _getAutoRate {
    my ($rate, $dev) = @_;

    if ( $rate eq "auto" ) {
        $rate = interfaceRate($dev);
        if (! defined $rate ) {
	    print STDERR "Interface $dev speed cannot be determined (assuming 10mbit)\n";
	    $rate = 10000000;
	}
    } else {
	$rate = getRate($rate);
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
    $self->{_level} = $level;

    $config->exists("default")
	or die "$level configuration not complete: missing default class\n";

    # make sure no clash of different types of tc filters
    my %matchTypes = ();
    foreach my $class ( $config->listNodes("class")) {
	foreach my $match ( $config->listNodes("class $class match") ) {
	    foreach my $type ( $config->listNodes("class $class match $match") ) {
		next if ($type eq 'description');
		$matchTypes{$type} = "$class match $match";
	    }
	}
    }

    if (scalar keys %matchTypes > 1 && $matchTypes{ip}) {
	print "Match type conflict:\n";
	while (my ($type, $usage) = each(%matchTypes)) {
	    print "   class $usage $type\n";
	}
	die "$level can not match on both ip and other types\n";
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
    my $default = shift @$classes;
    my $maxid = 1;

    $default->rateCheck($rate, "$self->{_level} default");

    foreach my $class (@$classes) {
	$class->rateCheck($rate, "$self->{_level} class $class->{id}");

	# find largest class id
	if (defined $class->{id} && $class->{id} > $maxid) {
	    $maxid = $class->{id};
	}
    }

    # fill in id of default
    $default->{id} = ++$maxid;
    unshift @$classes, $default;

    # Check if we need dsmrk
    my $usedsmark;
    foreach my $class (@$classes) {
	if (defined $class->{dsmark}) {
	    $usedsmark = 1;
	    last;
	}
    }

    my $parent = 1;
    my $root = "root";

    # if we need to change dsfield values, then put dsmark in front
    if ($usedsmark) {
	# dsmark max index must be power of 2
	my $indices = $maxid + 1;
	while (($indices & ($indices - 1)) != 0) {
	    ++$indices;
	}

	print {$out} "qdisc add dev $dev handle 1:0 root dsmark"
	    . " indices $indices default_index $default->{id} set_tc_index\n";

	foreach my $class (@$classes) {
	    $class->dsmarkClass($out, 1, $dev);
	    foreach my $match ($class->matchRules()) {
		$match->filter($out, $dev, 1, 1);
		printf {$out} " classid %x:%x\n", $parent, $class->{id};
	    }
	}

	$parent = $indices + 1;
	$root = "parent 1:1"
    }

    printf {$out} "qdisc add dev %s %s handle %x: htb default %x\n",
    	$dev, $root, $parent, $default->{id};
    printf {$out} "class add dev %s parent %x: classid %x:1 htb rate %s\n",
    	$dev, $parent, $parent, $rate;

    foreach my $class (@$classes) {
        $class->htbClass($out, $dev, $parent, $rate);

	foreach my $match ($class->matchRules()) {
	    $match->filter($out, $dev, $parent, 1, $class->{dsmark});
	    printf {$out} " classid %x:%x\n", $parent, $class->{id};
	}
    }
}

# Walk configuration tree and look for changed nodes
# The configuration system should do this but doesn't do it right
sub isChanged {
    my ($self, $name) = @_;
    my $config = new Vyatta::Config;

    $config->setLevel("qos-policy traffic-shaper $name");

    if ($config->isChanged('bandwidth') ) {
	return 'bandwidth';
    }

    foreach my $attr ('bandwidth', 'burst', 'ceiling', 'priority', 'queue-limit', 'queue-type') {
	if ($config->isChanged("default $attr")) {
	    return "default $attr";
	}
    }
    
    my %classNodes = $config->listNodeStatus('class');
    while (my ($class, $status) = each %classNodes) {
	if ($status ne 'static') {
	    return "class $class";
	}
	
	foreach my $attr ('bandwidth', 'burst', 'ceiling', 'priority', 'queue-limit', 'queue-type') {
	    if ($config->isChanged("class $class $attr")) {
		return "class $class $attr";
	    }
	}

	my %matchNodes = $config->listNodeStatus("class $class match");
	while (my ($match, $status) = each %matchNodes) {
	    my $level = "class $class match $match"; 
	    if ($status ne 'static') {
		return $level;
	    }
	    
	    foreach my $parm ('vif', 'interface', 'ip dscp', 'ip protocol', 
			      'ip source address', 'ip destination address',
			      'ip source port', 'ip destination port')  {
		if ($config->isChanged("$level $parm")) {
		    return "$level $parm";
		}
	    }
	}
    }

    return undef; # false
}

1;
