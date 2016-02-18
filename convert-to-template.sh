#!/bin/sh

# cleanup OS for template creation
# version 0.1
# cleans up the OS to turn into template for future deployments

# stop logging services
/sbin/service rsyslog stop
/sbin/service auditd stop

# remove old kernels
/bin/package-cleanup --oldkernels --count=1

# clean out yum
/usr/bin/yum clean all

# force the logs to rotate and blank out old logs
/usr/sbin/logrotate -f /etc/logrotate.conf
/bin/find /var/log/ -type f -exec /bin/sh -c '>{}' \;

# remove udev persistent device rules
/bin/rm -f /etc/udev/rules.d/70-*

# remove template MAC and UUID
if [ -f /etc/sysconfig/network-scripts/ifcfg-eth0 ]; then
  /bin/sed -i ‘/^(HWADDR|UUID)=/d’ /etc/sysconfig/network-scripts/ifcfg-eth0
fi

if [ -f /etc/sysconfig/network-scripts/ifcfg-eth1 ]; then
  /bin/sed -i ‘/^(HWADDR|UUID)=/d’ /etc/sysconfig/network-scripts/ifcfg-eth1
fi

# clean out tmp
/bin/rm -rf /tmp/*
/bin/rm -rf /var/tmp/*

# remote ssh host keys
/bin/rm -f /etc/ssh/*key*

# remove root's user shell history
history -c && history -w


# remove root's ssh stuff
/bin/rm -rf ~root/.ssh/
/bin/rm -f ~root/anaconda-ks.cfg

# touch /.unconfigured for RHEL6
touch /.unconfigured
