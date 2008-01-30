package VyattaQosPolicy;

use strict;

require VyattaConfig;
use VyattaQosTrafficShaper;
use VyattaQosFairQueue;

# Main class for all QoS policys
# It is a base class, and actual policies are subclass instances.

# Build a new traffic shaper of the proper type based
# on the configuration information.
sub config {
    my ( $class, $config, $type ) = @_;
    my $object = undef;

  SWITCH: {
        ( $type eq 'fair-queue' ) && do {
            $object = new VyattaQosFairQueue($config);
            last SWITCH;
        };

        ( $type eq 'traffic-shaper' ) && do {
            $object = new VyattaQosTrafficShaper($config);
            last SWITCH;
        };

        die "Unknown policy type \"$type\"\n";
    }
    return $object;
}

1;
