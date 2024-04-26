#!/bin/sh


# get total number of shards and size per instance from cat_shards.txt (GET _cat/shards?v)
#
#

# colors
red=`tput setaf 1`
green=`tput setaf 2`
blue=`tput setaf 14`
reset=`tput sgr0`

# help
if [ -z "${1}"  ]; then
  echo "${green}Usage :${reset} ${0} /path/cat_shards.txt"
  exit
fi

sum_and_convert_to_gb() {
    total_size_bytes=0

    while read line; do
        size=$(echo $line | sed -E 's/[^0-9.]//g')
        unit=$(echo $line | sed -E 's/[^bkmg]//g')

        case $unit in
          "b") total_size_bytes=$(echo "$total_size_bytes + $size" | bc) ;;
          "kb") total_size_bytes=$(echo "$total_size_bytes + ($size * 1024)" | bc) ;;
          "mb") total_size_bytes=$(echo "$total_size_bytes + ($size * 1024 * 1024)" | bc) ;;
          "gb") total_size_bytes=$(echo "$total_size_bytes + ($size * 1024 * 1024 * 1024)" | bc) ;;
        esac

    done

    total_size_gb=$(echo "scale=2; $total_size_bytes / 1024 / 1024 / 1024" | bc)
    echo $total_size_gb
}

fmt="%-40s%-10s%-12s\n"
printf "$fmt" "INSTANCE" "SHARDS" "SIZE(mb)"

for instance in `cat "${1}" | awk {' print $NF '} | grep -v "^node$" | sort |uniq`
do
  shards=`cat "${1}" | grep -c "${instance}"`
  size=`cat "${1}" | grep "${instance}" | awk {' print $7 '} | sum_and_convert_to_gb`


  printf "$fmt" "${instance}" "${shards}" "${size}"
done
