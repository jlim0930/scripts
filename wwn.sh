#!/bin/sh

# 0.2 - changed up the script a bit and added some other checks
# justin
# get wwn's 
# if you run it as root you will get the count of HBA's via lspci if not then just wwn's


# get vars
COUNT=`lspci | grep -c -i "Fibre Channel"`
HOSTNAME=`hostname`

# if COUNT is 0 then echo output and exit
if [ $COUNT -eq 0 ]
then
echo "No HBAs found on $HOSTNAME"
exit
fi

# 2.4 qlogic flag
FLAG=0
if [ `ls -1 /proc/scsi | grep -c qla` -ge 1 ]
then
FLAG=1
fi

# output
echo "$HOSTNAME contains $COUNT HBA : "

if [ $FLAG -eq 1 ]
then
  cat /proc/scsi/qla2xxx/* | grep adapter-port | awk -F= {' print $2 '} | cut -c 1-16
else
  for i in `ls -1 /sys/class/fc_host/`; do echo "WWN : `cat /sys/class/fc_host/$i/port_name | sed 's/0x//g'` PORT STATUS : `cat /sys/class/fc_host/$i/port_state`"; done
fi
