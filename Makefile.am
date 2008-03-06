cfgdir = $(datadir)/vyatta-cfg/templates
share_perl5dir = /opt/vyatta/share/perl5

bin_SCRIPTS =
sbin_SCRIPTS =
sysconf_DATA =
share_perl5_DATA =

sbin_SCRIPTS += scripts/vyatta-qos.pl
sbin_SCRIPTS += scripts/vyatta-qos-util.pl

share_perl5_DATA += scripts/VyattaQosUtil.pm
share_perl5_DATA += scripts/VyattaQosFairQueue.pm
share_perl5_DATA += scripts/VyattaQosTrafficShaper.pm
share_perl5_DATA += scripts/VyattaQosMatch.pm

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
  cpio -0pd

install-exec-hook:
	mkdir -p $(DESTDIR)$(cfgdir)
	cd templates; $(cpiop) $(DESTDIR)$(cfgdir)

