#!/bin/sh

# defs
TCPDUMP=/usr/sbin/tcpdump
IFCONFIG=/sbin/ifconfig
ETHTOOL=/sbin/ethtool
NETSTAT=/bin/netstat

# count total interfaces
TOTAL=`$IFCONFIG -a | grep -c "eth"`
printf "\nTotal physical interface count : $TOTAL\n\n"

# get details
if [ "$(id -u)" == "0" ] ; then
  printf "INTERFACE\tADDRESS(slave)\tNETMASK\t\tMAC\t\t\tLINK\tSPEED\t\tDUPLEX\n"
else
  printf "INTERFACE\tADDRESS(slave)\tNETMASK\t\tMAC\n"
fi

ip addr | grep inet | egrep -v "host lo|inet6" | while read line
do
  INTERFACE=$(echo $line | sed 's/^.* //')
  ADDRESS=$($IFCONFIG $INTERFACE | grep inet[^6] | awk '{ print $2 '} | grep -o -E "([[:digit:]]+\.){3}[[:digit:]]+"                                                                                                                          ;)
#  BCAST=$($IFCONFIG $INTERFACE | grep inet[^6] | awk '{ print $3 '} | grep -o -E "([[:digit:]]+\.){3}[[:digit:]]+";                                                                                                                          )
  NMASK=$($IFCONFIG $INTERFACE | grep inet[^6] | awk '{ print $4 '} | grep -o -E "([[:digit:]]+\.){3}[[:digit:]]+";)
  MAC=$($IFCONFIG $INTERFACE | grep HWaddr | awk {' print $5 '})
  if [ "$(id -u)" == "0" ] ; then
    LINK=$($ETHTOOL $INTERFACE | grep Link | awk {' print $3 '})
    SPEED=$($ETHTOOL $INTERFACE | grep Speed | awk {' print $2 '})
    DUPLEX=$($ETHTOOL $INTERFACE | grep Duplex | awk {' print $2 '})
  fi
  if [ `echo $INTERFACE | grep "bond"` ] ; then
    cat /proc/net/bonding/$INTERFACE | grep "Slave Interface" | awk {' print $3 '} | while read line2
        do
          if [ "$(id -u)" == "0" ] ; then
            BLINK=$($ETHTOOL $line2 | grep Link | awk {' print $3 '})
            BSPEED=$($ETHTOOL $line2 | grep Speed | awk {' print $2 '})
            BDUPLEX=$($ETHTOOL $line2 | grep Duplex | awk {' print $2 '})
          fi
          MAC=$(cat /proc/net/bonding/$INTERFACE | egrep "Slave Interface|MII Status|Permanent" | sed '1n;N;N;s/\n/                                                                                                                           /g' | grep $line2 | cut -d" " -f10 | tr '[:lower:]' '[:upper:]')
          LINK=$(cat /proc/net/bonding/$INTERFACE | egrep "Slave Interface|MII Status" | sed '1n;N;s/\n/ /g' | grep                                                                                                                           $line2 | cut -d" " -f6)
          PRIMARY=$(cat /proc/net/bonding/bond0 | grep Active | cut -d" " -f4)
          STATUS="BACKUP"
          if [ $PRIMARY == $line2 ]; then
            STATUS="ACTIVE"
          fi
          printf "$line2\t\t$INTERFACE\t\t$STATUS-$LINK\t$MAC\t$BLINK\t$BSPEED\t$BDUPLEX\n"
    done
  fi
  if [ "$(id -u)" == "0" ] ; then
    printf "$INTERFACE\t\t$ADDRESS\t$NMASK\t$MAC\t$LINK\t$SPEED\t$DUPLEX\n"
  else
    printf "$INTERFACE\t\t$ADDRESS\t$NMASK\t$MAC\n"
  fi
done

printf "\n"
$NETSTAT -rn
