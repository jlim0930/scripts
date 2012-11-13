#!/bin/sh

# this script will plumb up all the interfaces and grab its information
# version 0.2 - 2012-11-13 completely rewritten
# version 0.1 - inital

HOSTNAME=`hostname`
echo $HOSTNAME
echo ""

format="%10s%19s%16s%16s%8s%8s%12s%8s  %-s\n"
printf "$format" "INTERFACE" "MAC" "IP" "NETMASK" "SLAVE?" "LINK" "SPEED" "DUPLEX"
printf "$format" "---------" "---" "--" "-------" "------" "----" "-----" "------"

#printf "INT\tMAC\t\t\tIP\t\tNETMASK\t\t\tSLAVE\tLINK\tSPEED\tDUPLEX\n"

LIST=`ip link show | grep BROADCAST | awk {' print $2 '} | awk -F: {' print $1 '}`


for INTERFACE in $LIST
do
        # configure the interface up
        ifconfig $INTERFACE up

        # find the link status
        LINK="no"
        if [ `ip link show | grep $INTERFACE | grep -c MASTER` -eq 1 ]; then
          LINK="bonded"
        else
          LINK=`ethtool $INTERFACE | grep Link | awk {' print $3 '}`
        fi

        # if link is up find speed and duplex
        SPEED="n/a"
        DUPLEX="n/a"
        if [ $LINK == "yes" ]; then
          SPEED=`ethtool $INTERFACE | grep Speed | awk {' print $2 '}`
          DUPLEX=`ethtool $INTERFACE | grep Duplex | awk {' print $2 '}`
        fi

        # MAC address
        MAC=`ifconfig $INTERFACE | grep HWaddr | awk {' print $5 '}`
        if [ `ip link show | grep $INTERFACE | grep -c SLAVE` -eq 1 ]; then
          MAC=`cat /proc/net/bonding/bond* | egrep "Slave Interface|Permanent" | sed 'N;s/\n/ /' | grep $INTERFACE | awk {' print $7 '}`
        fi

        # IP address & netmask
        if [ `ifconfig $INTERFACE | grep -c 'inet addr'` -lt 1 ]; then
          IP="none    "
          NETMASK="none"
        else
          IP=`ifconfig $INTERFACE | grep "inet addr" | awk {' print $2 '} | awk -F: {' print $2 '}`
          NETMASK=`ifconfig $INTERFACE | grep "inet addr" | awk {' print $4 '} | awk -F: {' print $2 '}`
        fi

        # SLAVE ?
        if [ `ip link show | grep $INTERFACE | grep -c SLAVE` -eq 1 ]; then
          SLAVE=`ip link show | grep $INTERFACE | awk {' print $9 '}`
        else
          SLAVE="no"
        fi

#       printf "$INTERFACE\t$MAC\t$IP\t$NETMASK\t\t\t$SLAVE\t$LINK\t$SPEED\t$DUPLEX\n"
        printf "$format" $INTERFACE $MAC $IP $NETMASK $SLAVE $LINK $SPEED $DUPLEX
done

echo ""
# print routing table
netstat -rn
