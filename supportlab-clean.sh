#!/bin/sh
#
# please edit mystring to match your username
mystring="justinlim"


label="division=support,org=support,team=support,project=${mystring}"

for instance in $(gcloud compute instances list --format='value[separator=","](name,zone)' | grep ${mystring})
do
  name="${instance%,*}";
  zone="${instance#*,}";
  echo "Running docker image prune -a -f for ${name} in ${zone}"
  gcloud compute ssh ${name} --zone=${zone} --command="docker image prune -a -f" &
  # gcloud compute instances add-labels ${name} --zone=${zone} --labels="${label}"
done
