#!/usr/bin/env sh

## Creates GCP instances

# --------------EDIT information below
gcp_name="justinlim-lab"
##############################
gcp_project="elastic-support"
gcp_zone="us-central1-a"        # GCP zone - select one that is close to you
machine_type="e2-standard-4"    # GCP machine type - gcloud compute machine-types list
boot_disk_type="pd-ssd"         # disk type -  gcloud compute disk-types list
label="division=support,org=support,team=support,project=${gcp_name}"

# -------- do not edit below

# colors
red=`tput setaf 1`
green=`tput setaf 2`
blue=`tput setaf 14`
reset=`tput sgr0`

help() 
{
  echo "This script is to stand up a GCP environment in ${gcp_project} Project"
  echo ""
  echo "${green}Usage:${reset} ./`basename $0` COMMAND"
  echo "${blue}COMMANDS${reset}"
  echo "  ${green}create${reset} - Creates your GCP environment & run post-scripts(linux)"
  echo "           defaults to centos-7 if image is not specified"
  echo "           defaults to 1 gcp instance if number of instance is not specified"
  echo "  ${green}list${reset} - List all available images"
  echo "  ${green}find${reset} - Finds info about your GCP environment"
  echo "  ${green}delete${reset} - Deletes your GCP environment"

} # end help

# image_list
image_list() {
  echo "${green}[DEBUG]${reset} Full list of supported images"
  gcloud compute images list | grep -v arm | grep READY | grep "\-cloud " | awk {' print $3 '} | grep -v READY | sort -n
}

# find image
find_image() {
  unset STRING
  unset PROJECT
  unset IMAGE

  STRING=$(gcloud compute images list | grep -v arm | grep READY | grep "\-cloud " | grep "${1} " | tail -1)
  PROJECT=$(echo ${STRING} | awk {' print $2'})
  IMAGE=$(echo ${STRING} | awk {' print $1 '})
  if [ -z ${PROJECT} ]; then
    echo "${red}[DEBUG]${reset} Family: ${1} not found"
    help
    exit
  else
    echo "${green}[DEBUG]${reset} Found PROJECT: ${blue}${PROJECT}${reset} IMAGE: ${blue}${IMAGE}${reset}"
  fi
}

# wait_vm_up
wait_vm_up() {
  unset status
  while [ "${status}" != "done" ]
  do
    status=$(gcloud compute ssh ${gcp_name} --zone=${gcp_zone} --ssh-flag="-q" --command 'grep -m 1 "done" /ran_startup' 2>&-)
    echo "${red}[DEBUG]${reset} Building - takes about 5 minutes. will check again in 30 seconds."
    sleep 30
  done
  echo "${green}[DEBUG]${reset} READY! you can login via ${blue}gcloud compute ssh ${gcp_name}${reset}"
  echo "${green}[DEBUG]${reset} If you need to run anything via the browser you can open a ssh tunnel ${blue}gcloud compute ssh ${gcp_name} -- -L 9999:localhost:80${reset} where 9999 is the local port and 80 is the port on the vm"
  find
  exit
}

# find
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


# create
create() 
{
  find_image ${image}
  find
  
  for count in $(seq 1 ${max})
  do
    echo "${green}[DEBUG]${reset} Creating instance ${blue}${gcp_name}-${count}${reset} with ${blue}${image}${reset} total of ${blue}${max}${reset} instances"
    gcloud compute instances create ${gcp_name}-${count} \
      --labels ${label} \
      --project=${gcp_project} \
      --zone=${gcp_zone} \
      --machine-type=${machine_type} \
      --network-interface=network-tier=PREMIUM,subnet=default \
      --maintenance-policy=MIGRATE \
      --provisioning-model=STANDARD \
      --tags=http-server,https-server \
      --create-disk=auto-delete=yes,boot=yes,device-name=${gcp_name}-${count},image=projects/${PROJECT}/global/images/${IMAGE},mode=rw,type=projects/elastic-support/zones/${gcp_zone}/diskTypes/${boot_disk_type} \
      --metadata=startup-script='#!/usr/bin/env bash
      if [ ! -f /ran_startup ]; then
        curl -s https://raw.githubusercontent.com/jlim0930/scripts/master/gcp-postinstall.sh | bash
      fi'
 
    echo ""
  done
  echo "${green}[DEBUG]${reset} Compute instance is being deployed  Please ${blue}gcloud compute ssh ${gcp_name}-X [--zone ${gcp_zone}]${reset}.  There is a post install script running and it will reboot the instance once complete, usually in about 3-5 minutes."
  echo ""
  echo "${green}[DEBUG]${reset} If you are running windows instance.  Please create your password ${blue}gcloud compute reset-windows-password ${gcp_name}${reset}"
  sleep 5
  find
} # end create

delete() {
  if [ $(gcloud compute instances list 2> /dev/null --project ${gcp_project} | grep ${gcp_name} | wc -l) -gt 0 ]; then
    for instance in $(gcloud compute instances list | grep ${gcp_name} | awk {' print $1 '})
      do
        echo "${green}[DEBUG]${reset} Deleting ${instance}"
        gcloud compute instances delete ${instance} --project ${gcp_project} --zone=${gcp_zone} --quiet;
      done
  else 
    echo "${red}[DEBUG]${reset} Instance ${gcp_name} not found"
  fi
} # end delete

## main body
case ${1} in
  create|start)
    # Get image
    image_list
    read -p "Please select an image [centos-7] : " image
    echo ""
    if [ -z ${image} ]; then
      image="centos-7"
    fi
    # Get # of instances
    read -p "Please input number of instances [1] : " max
    echo ""
    if [ -z ${max} ]; then
      max="1"
    fi
    create ${image}
#    wait_vm_up
    ;;
  find|info|status|check)
    find
    ;;
  list|available)
    image_list
    ;;
  delete|cleanup|stop)
    delete
    ;;
  *)
    help
    ;;
esac
