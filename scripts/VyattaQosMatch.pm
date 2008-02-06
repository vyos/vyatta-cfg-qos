package VyattaQosMatch;
require VyattaConfig;
use VyattaQosUtil;
use strict;

my %fields = (
	_dev      => undef,
	_vif      => undef,
	_ip	  => {
	    src      => undef,
	    dst      => undef,
	    dsfield  => undef,
	    protocol => undef,
	    sport    => undef,
	    dport    => undef,
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

sub _define {
    my ( $self, $config ) = @_;
    my $level = $config->setLevel();

    $self->{_vif} = VyattaQosUtil::getIfIndex($config->returnValue("vif"));
    $self->{_dev} = $config->returnValue("interface");
    if ($config->exists("ip")) {
	my %ip;

	$ip{dsfield} = VyattaQosUtil::getDsfield( $config->returnValue("ip dsfield"));
	$ip{protocol} = VyattaQosUtil::getProtocol($config->returnValue("ip protocol"));
	$ip{src} = $config->returnValue("ip source address");
	$ip{dst} = $config->returnValue("ip destination address");
	$ip{sport} = $config->returnValue("ip source port");
	$ip{dport} = $config->returnValue("ip destination port");
	$self->{_ip} = \%ip;
    }
}

sub filter {
    my ( $self, $out, $dev, $id ) = @_;

    print {$out} "filter add dev $dev parent 1:0 prio 1";

    if (defined $self->{_ip}) {
	my $ip = $self->{_ip};
	print {$out} " protocol ip u32";
	print {$out} " match ip dsfield $$ip{dsfield} 0xff"	if defined $$ip{dsfield};
	print {$out} " match ip protocol $$ip{protocol} 0xff"   if defined $$ip{protocol};
	print {$out} " match ip src $$ip{src}"			if defined $$ip{src};
	print {$out} " match ip sport $$ip{sport} 0xffff"	if defined $$ip{sport};
	print {$out} " match ip dst $$ip{dst}"			if defined $$ip{dst};
	print {$out} " match ip dport $$ip{dport} 0xffff"	if defined $$ip{dport};
    }

    if (defined $self->{_dev}) {
	print {$out} " basic meta match meta \(rt_iif eq $self->{_dev}\)";
    }

    if (defined $self->{_vif}) {
	print {$out} " basic meta match meta \(vlan mask 0xfff eq $self->{_vif}\)";
    }

    print {$out} " classid 1:$id\n";
}
