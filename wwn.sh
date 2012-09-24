#!/bin/sh

# native way to get wwn info from the server. 2 different methods kernel 2.4 vs 2.6

COUNT=`lspci | egrep -c -i "qlog|emul"`
FLAG=0
HOSTNAME=`hostname`

# rhel4 or higher
RHEL4=0
if [ `grep -c Nahant /etc/redhat-release` = 1 ]
then
RHEL4=1
fi

if [ $COUNT -ge 1 ]
then
FLAG=1
fi

if [ $FLAG -eq 0 ]
then
echo "No HBAs found on $HOSTNAME"
exit
fi

echo "$HOSTNAME WWNs : "

if [ $RHEL4 -eq 1 ]
then
cat /proc/scsi/qla2xxx/* | grep adapter-port | awk -F= {' print $2 '} | cut -c 1-16
else
for i in `ls -1 /sys/class/fc_host/`; do cat /sys/class/fc_host/$i/port_name| sed 's/0x//g'; done
fi

