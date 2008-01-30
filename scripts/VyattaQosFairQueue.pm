package VyattaQosFairQueue;
@ISA = qw/VyattaQosPolicy/;

#
# This is a wrapper around Stochastic Fair Queue(SFQ) queue discipline
# Since SFQ is a hard to explain, use the name fair-queue since SFQ
# is most similar to Weighted Fair Queue (WFQ) on Cisco IOS.
#

use strict;

require VyattaConfig;

# Fair Queue
# Uses SFQ which is similar to (but not same as) WFQ

my %fields = (
    _perturb => undef,
    _limit   => undef,
);

sub new {
    my ( $that, $config ) = @_;
    my $class = ref($that) || $that;
    my $self = {%fields};

    $self->{_perturb} = $config->returnValue("rekey-interval");
    $self->{_limit}   = $config->returnValue("queue-limit");
    return bless $self, $class;
}

sub commands {
    my ( $self, $out, $dev ) = @_;
    
    print {$out} "qdisc add dev $dev root sfq";
    print {$out} " perturb $self->{_perturb}" if ( defined $self->{_perturb} );
    print {$out} " limit $self->{_limit}"     if ( defined $self->{_limit} );
    print "\n";
}

1;
