# Traffic shaper sub-class

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

package Vyatta::Qos::HFSCClass;
use strict;
use warnings;

require Vyatta::Config;
use Vyatta::Qos::Match;
use Vyatta::Qos::Util qw/getDsfield getTime getRate/;

sub new {
    my ( $that, $config, $id ) = @_;
    my $class = ref($that) || $that;
    my $self = {};

    $self->{id} = $id;

    bless $self, $class;

    if ($config) {
        my $level = $config->setLevel();

        $self->{level}     = $level;
        my @matches = _getMatch("$level match");
	
	# HFSC service curves
	$self->{_linkshare}  = ();
	$self->{_realtime}   = ();
	$self->{_upperlimit} = ();

	# Populate services curves using configuration
	foreach my $sc (qw(linkshare realtime upperlimit)) {
	    foreach my $type (qw(m1 m2)) {
		$self->{'_' . $sc}{$type} = $config->returnValue($sc . ' ' . $type);
	    }
	    my $delay = $config->returnValue($sc . ' d');
	    $self->{'_' . $sc}{d} = getTime($delay) if ($delay);
	}
	
        $self->{_match} = \@matches;
    }


    return $self;
}

sub _getMatch {
    my $level = shift;
    my @matches;
    my $config = new Vyatta::Config;

    foreach my $match ( $config->listNodes($level) ) {
        $config->setLevel("$level $match");
        my $match = new Vyatta::Qos::Match($config);
        if (defined($match)) {
            push @matches, $match;
        }
    }
    return @matches;
}

sub matchRules {
    my ($self) = @_;
    my $matches = $self->{_match};
    return @$matches;
}

sub _getPercentRate {
    my ( $rate, $speed ) = @_;
    return unless defined $rate;

    # Rate might be a percentage of speed
    if ( $rate =~ /%$/ ) {
        my $percent = substr( $rate, 0, length($rate) - 1 );
        if ( $percent < 0 || $percent > 100 ) {
            die "Invalid percentage bandwidth: $percent\n";
        }

        return ( $percent * $speed ) / 100.;
    } 

    return getRate($rate);
}

# Check rate configuration (%age or absolute values)
sub rateCheck {
    my ( $self, $ifspeed, $level ) = @_;

    # We need at least one M2 to be set
    if(!(defined $self->{_linkshare}{m2} || defined $self->{_realtime}{m2} || defined $self->{_upperlimit}{m2})) {
	print STDERR "Configuration error in: $level\n";
	print STDERR "At least one m2 value needs to be set";
	exit 1;
    }

    # Linkshare (or servicecurve) must be defined to use upperlimit
    if(defined $self->{_upperlimit}{m2} && !defined $self->{_linkshare}{m2}) {
	print STDERR "Configuration error in: $level\n";
	print STDERR "Linkshare m2 needs to be defined to use upperlimit m2";
	exit 1;
    }
    
    # Check that each m2 rate is below interface rate
    foreach my $sc (qw(linkshare realtime upperlimit)) {
	my $rate = _getPercentRate($self->{'_' . $sc}{m2}, $ifspeed);
	if(defined $rate && $rate > $ifspeed) {
	    print STDERR "Configuration error in: $level\n";
	    printf STDERR "$sc m2 value (%dKbps) must be less than the bw for the policy (%dKbps)", $rate / 1000, $ifspeed / 1000;
	    exit 1;
	}
    }
    # Same with m1 values, check that we have a matching m2 value and a valid d value
    foreach my $sc (qw(linkshare realtime upperlimit)) {
	if(defined $self->{'_' . $sc}{m1}) {
	    # m1 is set, we need a matching m2 value
	    if(!defined $self->{'_' . $sc}{m2}) {
	   	print STDERR "Configuration error in :$level\n";
	    	print STDERR "$sc m1 value is set, but no m2 was found !";
		exit 1;
	    }
	    # m1 is set, we need a matching d value
	    if(!defined $self->{'_' . $sc}{d}) {
		print STDERR "Configuration error in :$level\n";
		print STDERR "$sc m1 value is set, but no d was found !";
		exit 1;
	    }
	}
        my $rate = _getPercentRate($self->{'_' . $sc}{m1}, $ifspeed);
        if(defined $rate && $rate > $ifspeed) {
            print STDERR "Configuration error in: $level\n";
            printf STDERR "$sc m1 value (%dKbps) must be less than the bw for the policy (%dKbps)", $rate / 1000, $ifspeed / 1000;
	    exit 1;
        }
    }

}


sub get_rate {
    my ( $self, $speed ) = @_;

    return _getPercentRate( $self->{_rate}, $speed );
}

sub gen_class {
    my ( $self, $dev, $qdisc, $parent, $speed ) = @_;

    printf "class add dev %s parent %x:1 classid %x:%x hfsc",
      $dev, $parent, $parent, $self->{id};

    my $ret = '';
    # format : 'ul m1 Xbit d Yms m2 Xbit rt m2 Xbit' 
    foreach my $sc (qw(linkshare upperlimit realtime)) {
	# Translate long service curves names to short ones
	my %sc_short = (
	    'linkshare'  => 'ls',
	    'upperlimit' => 'ul',
	    'realtime'   => 'rt');
        if(defined $self->{'_' . $sc}{m2}) { # We have an m2 value, add curve to hfsc class
	    $ret .= ' ' . $sc_short{$sc} . ' ';
	    if(defined $self->{'_' . $sc}{m1} && defined $self->{'_' . $sc}{d}) { # We have m1 and d value, define curve
		$ret .= 'm1 ' . _getPercentRate($self->{'_' . $sc}{m1}, $speed) . ' d ' . $self->{'_' . $sc}{d} . ' ';
	    }
            $ret .= 'm2 ' . _getPercentRate($self->{'_' . $sc}{m2}, $speed);
        }
    }

    print $ret;
    print "\n";

    # Add SFQ qdisc
    
    printf "qdisc add dev %s parent %x:%x handle f%x: sfq perturb 10",
      $dev, $parent, $self->{id}, $self->{id};
    print "\n";
}


1;
