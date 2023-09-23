#!/usr/bin/env sh

## Creates GCP instances

# --------------EDIT information below

### PERSONAL ###################
gcp_name="justinlim-lab"

### ORGANIZATION ###############

gcp_project="elastic-support"
gcp_zone="us-central1-b"        # GCP zone - select one that is close to you
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
  echo "           defaults to rocky-linux-8-optimized-gcp if image is not specified"
  echo "  ${green}list${reset} - List all available images"
  echo "  ${green}find${reset} - Finds info about your GCP environment"
  echo "  ${green}delete${reset} - Deletes your GCP environment"
} # end help


# image_list
image_list() {
  echo "${green}[DEBUG]${reset} Full list of supported images"
  gcloud compute images list | grep -v arm | grep READY | grep "\-cloud " | awk {' print $3 '} | grep -v READY | sort -n
} # end image_list

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
  find_image ${image}
  echo ""
  echo "${green}[DEBUG]${reset} Creating instance ${blue}${gcp_name}-${count}${reset} with ${blue}${image}${reset}"
  if [ -z "$(echo ${image} | grep "window")" ]; then
    gcloud compute instances create ${gcp_name}-${count} \
      --quiet \
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
  else
    gcloud compute instances create ${gcp_name}-${count} \
      --quiet \
      --labels ${label} \
      --project=${gcp_project} \
      --zone=${gcp_zone} \
      --machine-type=${machine_type} \
      --network-interface=network-tier=PREMIUM,subnet=default \
      --maintenance-policy=MIGRATE \
      --provisioning-model=STANDARD \
      --tags=http-server,https-server \
      --create-disk=auto-delete=yes,boot=yes,device-name=${gcp_name}-${count},image=projects/${PROJECT}/global/images/${IMAGE},mode=rw,type=projects/elastic-support/zones/${gcp_zone}/diskTypes/${boot_disk_type}
    echo ""
  fi
  sleep 2
} # end create


## main body
case ${1} in
  create|start)
    find
    echo ""
    read -p "Please input the number of instances [1] : " max
    echo ""
    if [ -z ${max} ]; then
      max="1"
    fi

    for count in $(seq 1 ${max})
    do
      image_list
      read -p "Please select the image [rocky-linux-8-optimized-gcp] : " image
      echo ""
      if [ -z ${image} ]; then
        image="rocky-linux-8-optimized-gcp"
      fi
      echo "${green}[DEBUG]${reset} ${blue}${image}${reset} instance starting..."
      create ${image}
    done
    echo ""
    echo "===================================================================================================================================="
    echo ""
    echo "${green}[DEBUG]${reset} For ${blue}linux${reset} instances: Please ${blue}gcloud compute ssh ${gcp_name}-X [--zone ${gcp_zone}]${reset}.  There is a post install script running and it will reboot the instance once complete, usually in about 3-5 minutes."
    echo ""
    echo "${green}[DEBUG]${reset} For ${blue}windows${reset} instances: Please create your password ${blue}gcloud compute reset-windows-password ${gcp_name}-X[--zone ${gcp_zone}]${reset}"
    echo "${green}[DEBUG]${reset} Please open powershell(non-admin) and run the following lines to install mobaxterm/firefox/powertoys/other tools: "
    echo "${blue}[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12${reset}"
    echo "${blue}iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/jlim0930/scripts/master/gcp-postinstall.ps1'))${reset}"
    echo ""
    find
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













