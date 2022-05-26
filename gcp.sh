#!/bin/bash

## Creates a GCP instance
# ------- EDIT information below to customize for your needs
gcp_name="myname-lab"        # name of the compute instance stood up
gcp_project="project-name"   # project that you have access to to stand up the compute instance

gcp_zone="us-central1-a"        # GCP zone - select one that is close to you
machine_type="e2-standard-4"    # GCP machine type - gcloud compute machine-types list
boot_disk_size="20"             # boot disk size
boot_disk_type="pd-ssd"         # disk type -  gcloud compute disk-types list
image_project="centos-cloud"    # OS image - gcloud compute images list
image_family=`gcloud compute images list --project centos-cloud --no-standard-images | grep centos-7 | tail -n 1 | awk '{ print $1 }'`

# -------- do not edit below

# colors
red=`tput setaf 1`
green=`tput setaf 2`
blue=`tput setaf 4`
reset=`tput sgr0`

help() 
{
  echo "This script is to stand up a GCP environment in elastic-support"
  echo ""
  echo "${green}Usage:${reset} ./`basename $0` COMMAND"
  echo "${blue}COMMANDS${reset}"
  echo "  ${green}create${reset} - Creates your GCP environment"
  echo "  ${green}find${reset} - Finds info about your GCP environment"
  echo "  ${green}delete${reset} - Deletes your GCP environment"

} # end help

create() 
{
  find
  echo "${green}[DEBUG]${reset} Creating instance ${gcp_name}"
  echo ""
  gcloud compute instances create ${gcp_name} \
      --project=${gcp_project} \
      --zone=${gcp_zone} \
      --machine-type=${machine_type} \
      --network-interface=network-tier=PREMIUM,subnet=default \
      --maintenance-policy=MIGRATE \
      --tags=http-server,https-server \
      --create-disk=auto-delete=yes,boot=yes,device-name=${gcp_name},image=projects/centos-cloud/global/images/${image_family},mode=rw,size=${boot_disk_size},type=projects/elastic-support/zones/${gcp_zone}/diskTypes/${boot_disk_type} \
      --metadata=startup-script=\#\!/bin/sh$'\n'$'\n'if\ \[\ -f\ /ran_startup\ \]\;\ then$'\n'\ \ exit\;$'\n'fi$'\n'$'\n'curl\ -s\ https://raw.githubusercontent.com/jlim0930/scripts/master/gcp-postinstall.sh\ \|\ bash
 
  echo ""
  echo "${green}[DEBUG]${reset} Compute instance is ready to be used.  Please ${blue}gcloud compute ssh ${gcp_name}${reset}.  There is a post install script running and it will reboot the instance once complete, usually in about 2-3 minutes."
  
} # end start

wait_vm_up() {
  while [[  -z "${status}" ]]
  do
    status=$(gcloud compute ssh ${gcp_name} --zone=${gcp_zone} --ssh-flag="-q" --command 'grep -m 1 "done" /ran_startup' 2> /dev/null)
    echo "${red}[DEBUG]${reset} Building - takes about 5 minutes. will check again in 30 seconds."
    sleep 30
  done
  echo "${green}[DEBUG]${reset} READY! you can login via ${blue}gcloud compute ssh ${gcp_name}${reset}"
  echo "${green}[DEBUG]${reset} If you need to run anything via the browser you can open a ssh tunnel ${blue}gcloud compute ssh ${gcp_name} -- -L 9999:localhost:80${reset} where 9999 is the local port and 80 is the port on the vm"
  find
  exit
}


find() {
  # finds the info for your compute instance
  if [ $(gcloud compute instances list 2> /dev/null --project ${gcp_project} | grep ${gcp_name} | wc -l) -gt 0 ]; then
    echo "${green}[DEBUG]${reset} Instance found"
    echo ""
    gcloud compute instances list --filter="name:${gcp_name}"
    exit
  else
    echo "${red}[DEBUG]${reset} You dont have any instances running"
  fi
}  # end find

delete() {
  if [ $(gcloud compute instances list 2> /dev/null --project ${gcp_project} | grep ${gcp_name} | wc -l) -gt 0 ]; then
    echo "${green}[DEBUG]${reset} Deleting ${gcp_name}"
    gcloud compute instances delete ${gcp_name} --project ${gcp_project} --zone=${gcp_zone} --quiet;

  else 
    echo "${red}[DEBUG]${reset} Instance ${gcp_name} not found"
  fi
} # end delete

case ${1} in
  create|start)
    create
#    wait_vm_up
    ;;
  find|info|status|check)
    find
    ;;
  delete|cleanup|stop)
    delete
    ;;
  *)
    help
    ;;
esac
