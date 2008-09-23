cfgdir = $(datadir)/vyatta-cfg/templates
share_perl5dir = /opt/vyatta/share/perl5

sbin_SCRIPTS = scripts/vyatta-qos.pl
sbin_SCRIPTS += scripts/vyatta-qos-util.pl

share_perl5_DATA = scripts/VyattaQosUtil.pm
share_perl5_DATA += scripts/VyattaQosFairQueue.pm
share_perl5_DATA += scripts/VyattaQosTrafficShaper.pm
share_perl5_DATA += scripts/VyattaQosMatch.pm
share_perl5_DATA += scripts/VyattaQosRateLimiter.pm
share_perl5_DATA += scripts/VyattaQosDropTail.pm
share_perl5_DATA += scripts/VyattaQosTrafficLimiter.pm

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
  cpio -0pd

install-exec-hook:
	mkdir -p $(DESTDIR)$(cfgdir)
	cd templates; $(cpiop) $(DESTDIR)$(cfgdir)

