#!/bin/sh

# this script will run the command specified in CMD against a list of
# hosts in list_file and take logs while it runs 
# it will exit if the list is empty

CMD="xxxxx"

[ $# = 0 ] && echo "$0 list_file" && exit 1

for host in `cat $i`
do
	echo "$host: " | tee -a $$.out
	ssh $host "$CMD" | tee -a $$.out
	echo
done
