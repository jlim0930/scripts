#!/bin/sh
#
# get various server information
# getting vars
#
# CPU INFO
CPUMODEL=`cat /proc/cpuinfo  | grep "model name" | uniq | awk -F: {' print $2 '} | sed 's/  *//g'`
PHYSICALCPU=`cat /proc/cpuinfo | grep "physical id" | sort -n | uniq | grep -c id`
CORESPERCPU=`cat /proc/cpuinfo | grep "core id" | sort -n | uniq | grep -c id`
#
# MEMORY INFO
PHYSICALMEMORY=`free -m | grep Mem | awk {' print $2 '}`
SWAPMEMORY=`free -m | grep Swap | awk {' print $2 '}`
#
# chassis
SERIAL=`dmidecode | grep "Serial Number" | head -1 | sed 's/Serial Number: //g'  | sed 's/\t//g'`
#
# DISK
LOCALDISK=` mount | grep boot | awk {' print $1 '} | sed 's/1//g'`
TOTALLOCALDISK=`fdisk -l | grep "$LOCALDISK:" | awk -F: {' print $2 '} | awk -F, {' print $1 '}`
# MISC
ARCH=`uname -m`
KERNEL=`uname -r`
TZ=`date | awk {' print $5 '}`
#
# rhel4 or higher
RHEL4=0
if [ `grep -c Nahant /etc/redhat-release` = 1 ]
then
RHEL4=1
fi

echo "HOSTNAME : "
hostname
echo ""
echo "SERIAL NUMBER : $SERIAL"
echo ""
echo "CPU MODEL : $CPUMODEL"
echo "NUMBER OF PHYSICAL SOCKETS : $PHYSICALCPU"
echo "NUMBER OF CORES PER CPU : $CORESPERCPU"
echo ""
echo "PHYSICAL MEMORY : $PHYSICALMEMORY"
echo "SWAP MEMORY : $SWAPMEMORY"
echo ""
echo "Arch : $ARCH"
echo "Kernel : $KERNEL"
echo "Release : "
cat /etc/redhat-release
echo "Time Zone : $TZ"
echo ""
echo "resolv.conf"
cat /etc/resolv.conf
echo ""
echo "NTP servers"
cat /etc/ntp.conf | grep server | grep -v ^#
echo ""
echo "Total Local Disk : $TOTALLOCALDISK"
echo ""
echo "WWN : "
if [ $RHEL4 -eq 1 ]
then
cat /proc/scsi/qla2xxx/* | grep adapter-port | awk -F= {' print $2 '} | cut -c 1-16 | sed 'N;s/\n/\,/'
else
for i in `ls -1 /sys/class/fc_host/`; do cat /sys/class/fc_host/$i/port_name| sed 's/0x//g'; done | sed 'N;s/\n/\,/'
fi
echo ""
if [ $RHEL4 -eq 1 ]
then
echo "Powerpath :"
powermt display dev=all
else
echo "multipath :"
multipath -l
fi
echo ""
echo "pvs"
pvs
echo "vgs"
vgs
echo "lvs"
lvs
echo "df -h"
df -h
echo "/etc/fstab"
cat /etc/fstab
echo ""
echo "Interfaces :"
ifconfig -a | grep addr
cat /proc/net/bonding/bond*
netstat -rn
echo ""
echo ""
echo ""
echo ""
