# Random Detect
#
# This Qos module uses DSMARK and GRED to provide a policy
# similar to Cisco Weighted Random Detect.
#
# See Almesberger, Werner; Hadi Salim, Jamal; Kuznetsov, Alexey
# "Differentiated Services on Linux"
# http://www.almesberger.net/cv/papers/18270721.pdf
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

package Vyatta::Qos::FairBlue;
use strict;
use warnings;

require Vyatta::Config;
use Vyatta::Qos::Util qw/getRate getAutoRate getTime/;

my %qdiscOptions = (
    'priority'      => \&prioQdisc,
    'fair-queue'    => \&sfqQdisc,
    'drop-tail'     => \&fifoQdisc,
);

# Create a new instance based on config information
sub new {
    my ( $that, $config, $name ) = @_;
    my $level = $config->setLevel();

    my $target = $config->returnValue("queue-target");
    die "queue-target configuration missing\n" unless $target;
    my $limit = $config->returnValue("queue-limit");
    die "queue-limit configuration missing\n" unless $limit;
    my $type = $config->returnValue("queue-type");
    $type = "fair-queue" if (!defined($type));
 
    my $pburst = $config->returnValue("penalty burst");
    my $prate = $config->returnValue("penalty rate");

    my $self = {};
    my $class = ref($that) || $that;
    bless $self, $class;

    $self->{_target} = $target;
    $self->{_limit}  = $limit;
    $self->{_type}   = $type;
    $self->{_pburst} = $pburst;
    $self->{_prate}  = $prate;

    sfqValidate($self, $level) if ($self->{_type} eq "fair-queue");

    return $self;
}

sub sfqValidate {
    my ( $self, $level ) = @_;
    my $limit = $self->{_limit};

    if ( defined $limit && $limit > 127 ) {
        die "queue limit must be between 1 and 127 for queue-type fair-queue\n";
    }
}

sub prioQdisc {
    my ( $self, $dev ) = @_;
    my $prio_id = 0x4000 + $self->{id};
    my $limit   = $self->{_limit};

    printf "handle %x: prio\n", $prio_id;

    if ($limit) {
        foreach my $i (qw/1 2 3/) {
            printf "qdisc add dev %s parent %x:%x pfifo limit %d\n",
              $dev, $prio_id, $i, $limit;
        }
    }
}

sub sfqQdisc {
    my ( $self, $dev ) = @_;

    print "sfq perturb 10";
    print " limit $self->{_limit}" if ( $self->{_limit} );
    print "\n";
}

sub fifoQdisc {
    my ( $self, $dev ) = @_;

    print "pfifo";
    print " limit $self->{_limit}" if ( $self->{_limit} );
    print "\n";
}

sub gen_leaf {
    my ( $self, $dev, $parent ) = @_;
    my $qtype = $self->{_type};
    return unless $qtype;    # default is okay

    my $q = $qdiscOptions{$qtype};
    die "Unknown queue-type $qtype\n"
      unless $q;

    printf "qdisc add dev %s parent %x:%x ", $dev, $parent, 0;
    $q->( $self, $dev );
}

sub commands {
    my ( $self, $dev ) = @_;
    my $root = 1;
    printf("qdisc add dev %s root handle %x:0 sfb limit %d target %d ",
             $dev, $root, $self->{_limit}, $self->{_target});
    printf(" penalty_rate %d ", $self->{_prate}) if (defined $self->{_prate});
    printf(" penalty_burst %d", $self->{_pburst}) if (defined $self->{_pburst});
    print("\n");
    gen_leaf( $self, $dev, $root);     
}

1;
