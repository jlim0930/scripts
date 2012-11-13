#!/bin/sh

# this script will launch MAXFORK amount of processes against a list
# monitor it and wait for it to finish before launching additional 

MAXFORK=20
CMD="xxxxxxx'
DEAD_ONLY=0

[ $# -eq 0 ] && echo "Usage: $0 [-d] list_file" && exit 1

[$1 = "-d" ] && DEAD_ONLY=1 && shift 1

i=0
for host in `cat $1`
do
  (
	eval $CMD
  ) &

 i=$((i+1))
 while [ "$(jobs -r -p | wc -l)" -ge $MAXFORK ]; do
    sleep 1
  done
done

if [ -n "$(jobs -r -p)" ]; then
  wait
fi
