package VyattaQosMatch;
require VyattaConfig;
use VyattaQosUtil;
use strict;

my %fields = (
	_dev      => undef,
	_vlan     => undef,
	_ip	  => {
	    _src      => undef,
	    _dst      => undef,
	    _dsfield  => undef,
	    _protocol => undef,
	    _sport    => undef,
	    _dport    => undef,
	}
);

sub new {
    my ( $that, $config ) = @_;
    my $self = {%fields};
    my $class = ref($that) || $that;

    bless $self, $class;
    $self->_define($config);

    return $self;
}

sub _tos {
    my $tos = shift;
    my $ret = undef;

    if ( defined $tos ) {
        $ret = VyattaQosUtil::getDsfield($tos);
        if ( !defined $ret ) {
            $tos = hex($tos);
        }
    }
    return $ret;
}

sub _define {
    my ( $self, $config ) = @_;

    my $level=$config->setLevel();

    $self->{_vlan} = $config->returnValue("vif");
    $self->{_dev} = $config->returnValue("interface");

    $self->{_ip}->{_tos} = _tos( $config->returnValue("ip tos") );
    $self->{_ip}->{_protocol} = $config->returnValue("ip protocol");
    $self->{_ip}->{_src} = $config->returnValue("ip source address");
    $self->{_ip}->{_dst} = $config->returnValue("ip destination address");
    $self->{_ip}->{_sport} = $config->returnValue("ip source port");
    $self->{_ip}->{_dport} = $config->returnValue("ip source dport");
}

sub filter {
    my ( $self, $out, $dev, $id ) = @_;

    print {$out} "filter add dev $dev parent 1:0 prio 10";

    # TODO match on vlan, device, ...
    if (defined $self->{_ip}) {
	print {$out} " u32";
	print {$out} " match ip tos $self->{_ip}->{_tos} 0xff"
	    if defined $self->{_ip}->{_tos};
	print {$out} " match ip protocol $self->{_ip}->{_protcol} 0xff"
	    if defined $self->{_ip}->{_protocol};
	print {$out} " match ip src $self->{_ip}->{_src}"
	    if defined $self->{_ip}->{_src};
	print {$out} " match ip sport $self->{_ip}->{_sport}"
	    if defined $self->{_ip}->{_sport};
	print {$out} " match ip dst $self->{_ip}->{_dst}"
	    if defined $self->{_ip}->{_dst};
	print {$out} " match ip dport $self->{_ip}->{_dport}"
	    if defined $self->{_ip}->{_dport};
    }

    print {$out} " classid $id\n";
}
