package VyattaQosUtil;
use POSIX;
require Exporter;
@EXPORT	= qw/getRate getSize getProtocol getDsfield getIfIndex interfaceRate/;
use strict;

sub get_num  {
    my ($str) = @_;
    
    # clear errno
    $! = 0;
    my ($num, $unparsed) = POSIX::strtod($str);
    if (($str eq '') || $!) {
	die "Non-numeric input \"$str\"" . ($! ? ": $!\n" : "\n");
    }

    if ($unparsed > 0) { return $num, substr($str, -$unparsed); }
    else	       { return $num; }
}

## get_rate("10mbit")
# convert rate specification to number
# from tc/tc_util.c
sub getRate {
    my ($num, $suffix) = get_num(@_);

    if (defined $suffix) {
      SWITCH: {
	  ($suffix eq 'bit')	&& do { last SWITCH; };
	  ($suffix eq 'kibit')	&& do { $num *= 1024.; last SWITCH };
	  ($suffix eq 'kbit')	&& do { $num *= 1000.,; last SWITCH; };
	  ($suffix eq 'mibit')	&& do { $num *= 1048576.,; last SWITCH; };
	  ($suffix eq 'mbit')	&& do { $num *= 1000000.,; last SWITCH; };
	  ($suffix eq 'gibit')	&& do { $num *= 1073741824.,; last SWITCH; };
	  ($suffix eq 'gbit')	&& do { $num *= 1000000000.,; last SWITCH; };
	  ($suffix eq 'tibit')	&& do { $num *= 1099511627776.,; last SWITCH; };
	  ($suffix eq 'tbit')	&& do { $num *= 1000000000000.,; last SWITCH; };
	  ($suffix eq 'bps')	&& do { $num *= 8.,; last SWITCH; };
	  ($suffix eq 'kibps')	&& do { $num *= 8192.,; last SWITCH; };
	  ($suffix eq 'kbps')	&& do { $num *= 8000.,; last SWITCH; };
	  ($suffix eq 'mibps')	&& do { $num *= 8388608.,; last SWITCH; };
	  ($suffix eq 'mbps')	&& do { $num *= 8000000.,; last SWITCH; };
	  ($suffix eq 'gibps')	&& do { $num *= 8589934592.,; last SWITCH; };
	  ($suffix eq 'gbps')	&& do { $num *= 8000000000.,; last SWITCH; };
	  ($suffix eq 'tibps')	&& do { $num *= 8796093022208.,; last SWITCH; };
	  ($suffix eq 'tbps')	&& do { $num *= 8000000000000.,; last SWITCH; };

	  die "Rate must be a number followed by a optional suffix (kbit, mbps, ...)\n";
	}
    } else {
	# No suffix implies Kbps just as IOS
	$num *= 8000;
    }
    
    ($num >= 0) or die "Negative rate not allowed\n";
    return $num;
}

sub getSize {
    my ($num, $suffix) = get_num(@_);

    if (defined $suffix) {
      SWITCH: {
	  ($suffix eq 'b')		&& do { $num *= 1.,; last SWITCH; };
	  ($suffix eq 'k')		&& do { $num *= 1024.,; last SWITCH; };
	  ($suffix eq 'kb')		&& do { $num *= 1024.,; last SWITCH; };
	  ($suffix eq 'kbit')	&& do { $num *= 128.,; last SWITCH; };
	  ($suffix eq 'm')		&& do { $num *= 1048576.,; last SWITCH; };
	  ($suffix eq 'mb')		&& do { $num *= 1048576.,; last SWITCH; };
	  ($suffix eq 'mbit')	&& do { $num *= 131072.,; last SWITCH; };
	  ($suffix eq 'g')		&& do { $num *= 1073741824.,; last SWITCH; };
	  ($suffix eq 'gb')		&& do { $num *= 1073741824.,; last SWITCH; };
	  ($suffix eq 'gbit')	&& do { $num *= 134217728.,; last SWITCH; };
	  
	  die "Unknown suffix \"$suffix\"\n";
	}
    }
    
    die "Negative size not allowed\n"  if ($num < 0);
    return $num;
}

sub getProtocol {
    my ($str) = @_;

    defined $str or return;
    if ($str =~ /^([0-9]+)|(0x[0-9a-fA-F]+)$/) {
	if ($str < 0 || $str > 255) {
	    die "$str is not a valid protocol number\n";
	}
	return $str;
    }

    my ($name, $aliases, $proto) =  getprotobyname($str);
    (defined $proto)  or die "\"$str\" unknown protocol\n";
    return $proto;
}

# Parse /etc/iproute/rt_dsfield 
# return a hex string "0x10" or undefined
sub getDsfield {
    my ($str) = @_;
    my $match = undef;
    my $dsFileName = '/etc/iproute2/rt_dsfield';
    
    defined $str or return;

    if ($str =~ /^([0-9]+)|(0x[0-9a-fA-F]+)$/) {
	if ($str < 0 || $str > 255) {
	    die "$str is not a valid dsfield value\n";
	}
	return $str;
    }

    open my $ds, '<', $dsFileName || die "Can't open $dsFileName, $!\n";
    while (<$ds>) {
	next if /^#/;
	chomp;
	my ($value, $name) = split;
	if ($str eq $name) {
	    $match = $value;
	    last;
	}
    }
    close($ds) or die "read $dsFileName error\n";

    return $match;
}

sub getIfIndex {
    my ($str) = @_;

    defined $str or return;
    open my $sysfs, "<", "/sys/class/net/$str/ifindex" || die "Unknown interface $str\n";
    my $ifindex = <$sysfs>;
    close($sysfs) or die "read sysfs error\n";
    return $ifindex;
}


## interfaceRate("eth0")
# return result in bits per second
sub interfaceRate {
    my ($interface) = @_;
    my $config = new VyattaConfig;

    $config->setLevel("interfaces ethernet");
    if ($config->exists("$interface")) {
	my $speed  = $config->returnValue("$interface speed");
	if (defined($speed) && $speed ne "auto") {
	    return $speed * 1000000;
	}
    } 

    return ethtoolRate($interface);
}

## ethtoolRate("eth0")
# Fetch actual rate using ethtool and format to valid tc rate
sub ethtoolRate {
    my ($dev) = @_;
    my $rate = undef;

    open my $ethtool, "ethtool $dev |" or die "ethtool failed: $!\n";

    # ethtool produces:
    #
    # Settings for eth1:
    # Supported ports: [ TP ]
    # ...
    # Speed: 1000Mb/s
    while (<$ethtool>) {
	my @line = split;
	if ($line[0] =~ /^Speed:/) {
	    $rate = $line[1];
	    $rate =~ s#Mb/s#000000#;
	    last;
	}
    }
    close $ethtool;
    return $rate;
}
