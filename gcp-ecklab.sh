#!/usr/bin/env sh

## Creates GCP instances

# --------------EDIT information below

### PERSONAL ###################
gcp_name="$(whoami | sed $'s/[^[:alnum:]\t]//g')-ecklab"    # GCP name will automatically set to your username with special chars removed-eck
gcp_zone="us-central1-b"        # GCP zone - select one that is close to you

### ORGANIZATION ###############

gcp_project="elastic-support"
machine_type="e2-standard-8"    # GCP machine type - gcloud compute machine-types list
boot_disk_type="pd-ssd"         # disk type -  gcloud compute disk-types list
label="division=support,org=support,team=support,project=${gcp_name}"

# -------- do not edit below


# colors
bold=`tput bold`
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
  echo "           defaults to rocky-linux-8-optimized-gcp if image is not specified"
  echo "  ${green}find${reset} - Finds info about your GCP environment"
  echo "  ${green}delete${reset} - Deletes your GCP environment"
} # end help

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
} # end find_image

# find
find() {
  # finds the info for your compute instance
  if [ $(gcloud compute instances list  --project ${gcp_project} 2> /dev/null | grep ${gcp_name} | wc -l) -gt 0 ]; then
    echo "${green}[DEBUG]${reset} Instance(s) found"
    echo ""
    # gcloud compute instances list --project ${gcp_project} --filter="name:${gcp_name}"
    gcloud compute instances list --project ${gcp_project} --filter="name:${gcp_name}" --format="table[box] (name, zone.basename(), machineType.basename(), status, networkInterfaces[0].networkIP, networkInterfaces[0].accessConfigs[0].natIP, disks.licenses)"
  else
    echo "${red}[DEBUG]${reset} You dont have any instances running"
  fi
}  # end find

delete() {
  if [ $(gcloud compute instances list --project ${gcp_project} 2> /dev/null | grep ${gcp_name} | wc -l) -gt 0 ]; then
    for instance in $(gcloud compute instances list --project ${gcp_project} | grep ${gcp_name} | awk {' print $1 '})
      do
        echo "${green}[DEBUG]${reset} Deleting ${instance}"
        gcloud compute instances delete ${instance} --project ${gcp_project} --zone=${gcp_zone} --quiet
      done
  else
    echo "${red}[DEBUG]${reset} Instance ${gcp_name} not found"
  fi
} # end delete


# create
create()
{
  # find_image ${image}
  echo "${green}[DEBUG]${reset} Creating instance ${blue}${gcp_name}${reset} with ${blue}${image}${reset}"
  #gcloud compute instances create ${gcp_name} \
  #  --quiet \
  #  --labels ${label} \
  #  --project=${gcp_project} \
  #  --zone=${gcp_zone} \
  #  --machine-type=${machine_type} \
  #  --network-interface=network-tier=PREMIUM,subnet=default \
  #  --maintenance-policy=MIGRATE \
  #  --provisioning-model=STANDARD \
  #  --tags=http-server,https-server \
  #  --stack-type=IPV4_IPV6 \
  #  --create-disk=auto-delete=yes,boot=yes,device-name=${gcp_name},image=projects/${PROJECT}/global/images/${IMAGE},mode=rw,type=projects/elastic-support/zones/${gcp_zone}/diskTypes/${boot_disk_type} \
  #  --metadata=startup-script='#!/bin/sh
  #  if [ ! -f /ran_startup ]; then
  #    curl -s https://raw.githubusercontent.com/jlim0930/scripts/master/gcp-postinstall-ecklab.sh | sh
  #  fi
  #  '

  gcloud compute instances create ${gcp_name} \
    --quiet \
    --image-family rocky-linux-8-optimized-gcp \
    --image-project rocky-linux-cloud \
    --zone ${gcp_zone} \
    --labels ${label} \
    --machine-type ${machine_type} \
    --tags=http-server,https-server \
    --metadata=startup-script='#!/bin/sh
    if [ ! -f /ran_startup ]; then
      curl -s https://raw.githubusercontent.com/jlim0930/scripts/master/gcp-postinstall-ecklab.sh | sh
    fi
    '
  echo ""

  sleep 2
} # end create


## main body
case ${1} in
  create|start)
    image="rocky-linux-8-optimized-gcp"
    echo "${green}[DEBUG]${reset} ${blue}${image}${reset} instance starting on ${blue}${machine_type}${reset} in ${blue}${gcp_zone}${reset}"
    create ${image}

    echo ""
    echo "===================================================================================================================================="
    echo ""
    echo "${blue}[DEBUG]${reset} ${bold}There is a post install script running and it will reboot the instance once complete, usually in about 3-5 minutes.${reset}"
    echo "${green}[DEBUG]${reset} Please ${blue}gcloud compute ssh ${gcp_name} [--zone ${gcp_zone}]${reset}."
    echo ""
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













