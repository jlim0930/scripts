#!/usr/bin/env sh

## Creates GCP instances

# -------------- EDIT information below

### ORGANIZATION ###############

gcp_project="elastic-support"
REGION="us-central1"
# gcp_zone="us-central1-b"        # GCP zone - select one that is close to you
machine_type="e2-standard-4"    # GCP machine type - gcloud compute machine-types list
boot_disk_type="pd-ssd"         # disk type -  gcloud compute disk-types list
label="division=support,org=support,team=support,project=gcp-lab"

# --------------  Do not edit below

### PERSONAL ###################
gcp_name="$(whoami | sed $'s/[^[:alnum:]\t]//g')-lab"

# colors
red=$(tput setaf 1)
green=$(tput setaf 2)
blue=$(tput setaf 14)
reset=$(tput sgr0)

# Function to display help
help() {
  cat << EOF
This script is to stand up a GCP environment in ${gcp_project} Project

${green}Usage:${reset} ./$(basename "$0") COMMAND
${blue}COMMANDS${reset}
  ${green}create|start${reset}             - Creates your GCP environment & runs post-scripts (Linux)
  ${green}find|info|status|check${reset}   - Finds info about your GCP environment
  ${green}delete|cleanup|stop${reset}      - Deletes your GCP environment
EOF
}

debug() {
  echo "${green}[DEBUG]${reset} $1"
}

debugr() {
  echo "${red}[DEBUG]${reset} $1"
}

# load image list
load_image_list() {
  debug "Generating a list of supported images"
  image_list=$(gcloud compute images list --format="table(name, family, selfLink)" --filter="-name=sql AND -name=sap" | grep -v arm | grep "\-cloud" | sort)
  IFS=$'\n' read -r -d '' -a images <<< "$image_list"

  if [ -z "$image_list" ]; then
    debugr "No images found with the specified filters."
    exit 1
  fi

  families=($(echo "$image_list" | awk '{print $2}' | sort -u))
} # end

select_image() {
  debug "Select an image family:"
  original_columns=$COLUMNS
  COLUMNS=1
  select selected_family in "${families[@]}"; do
    if [ -n "$selected_family" ]; then
      selected_image=$(echo "$image_list" | grep "$selected_family" | head -n 1)
      selected_image_name=$(echo "$selected_image" | awk '{print $1}')
      selected_project=$(echo "$selected_image" | awk '{print $3}')
      break
    else
      debugr "Invalid selection. Please try again."
    fi
  done
  COLUMNS=$original_columns
}


# find
find_instances() {
  instance_count=$(gcloud compute instances list --project "${gcp_project}" --filter="name:${gcp_name}" --format="value(name)" | wc -l)
  if [ "$instance_count" -gt 0 ]; then
    debug "Instance(s) found"
    gcloud compute instances list --project "${gcp_project}" --filter="name:${gcp_name}" --format="table[box](name, zone.basename(), machineType.basename(), status, networkInterfaces[0].networkIP, networkInterfaces[0].accessConfigs[0].natIP, disks[0].licenses[0].basename())"
  else
    debugr "No instances found"
  fi
}

delete_instances() {
  instancelist=$(gcloud compute instances list --project "${gcp_project}" --filter="name:${gcp_name}" --format="value(name,zone)")
  if [ -z "$instancelist" ]; then
    debugr "No instances found with name ${gcp_name}"
    return 0
  fi

  # Iterate over the list of instances and delete them
  while read -r instance_name instance_zone; do
    debug "Deleting instance ${blue}$instance_name${reset} in zone ${blue}${instance_zone}${reset}..."
    gcloud compute instances delete "$instance_name" --zone="$instance_zone" --delete-disks all --quiet
  done <<< "$instancelist"
}

# delete_instances() {
#   instance_count=$(gcloud compute instances list --project "${gcp_project}" --filter="name:${gcp_name}" --format="value(name)" | wc -l)
#   if [ "$instance_count" -gt 0 ]; then
#     debug "Deleting instances"
#     gcloud compute instances delete $(gcloud compute instances list --project "${gcp_project}" --filter="name:${gcp_name}" --format="value(name)") --project "${gcp_project}" --zone="${gcp_zone}" --quiet
#   else
#     debugr "No instances found with name ${gcp_name}"
#   fi
# }

get_random_zone() {
  local zone_array=($zones)
  local zone_count=${#zone_array[@]}
  local random_index=$((RANDOM % zone_count))
  local selected_zone=${zone_array[$random_index]}

  echo $selected_zone
}

create_instances() {
  read -p "${green}[DEBUG]${reset} Please input the number of instances [1]: " max
  max="${max:-1}"

  load_image_list

  zones=$(gcloud compute zones list --filter="region:(${REGION})" --format="value(name)")


  for count in $(seq 1 "$max"); do
    select_image
    gcp_zone=$(get_random_zone)
    echo ""
    debug "Creating instance ${blue}${gcp_name}-${count}${reset} with image ${blue}${selected_image_name}${reset}"
    echo ""
    if [ -z "$(echo ${selected_image_name} | grep "window")" ]; then
      gcloud compute instances create ${gcp_name}-${count} \
        --quiet \
        --labels ${label} \
        --project=${gcp_project} \
        --zone=${gcp_zone} \
        --machine-type=${machine_type} \
        --network-interface=network-tier=PREMIUM,subnet=support-lab-vpc-us-sub1 \
        --maintenance-policy=MIGRATE \
        --provisioning-model=STANDARD \
        --tags=http-server,https-server \
        --stack-type=IPV4_IPV6 \
        --create-disk=auto-delete=yes,boot=yes,device-name=${gcp_name}-${count},image=projects/${selected_project}/global/images/${selected_image_name},mode=rw,type=projects/elastic-support/zones/${gcp_zone}/diskTypes/${boot_disk_type} \
        --metadata=startup-script='#!/usr/bin/env bash
        if [ ! -f /ran_startup ]; then
          curl -s https://raw.githubusercontent.com/jlim0930/scripts/master/gcp-postinstall.sh | bash
        fi' >/dev/null 2>&1
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
        --stack-type=IPV4_IPV6 \
        --create-disk=auto-delete=yes,boot=yes,device-name=${gcp_name}-${count},image=projects/${selected_project}/global/images/${selected_image_name},mode=rw,type=projects/elastic-support/zones/${gcp_zone}/diskTypes/${boot_disk_type} >/dev/null 2>&1
      echo ""
    fi
  done

  find_instances

  cat << EOF

====================================================================================================================================

${green}[DEBUG]${reset} For ${blue}linux${reset} instances:
  ${green}[DEBUG]${reset} Please ${blue}gcloud compute ssh ${gcp_name}-X [--zone ${gcp_zone}]${reset}.
  ${green}[DEBUG]${reset} There is a post install script running and it will reboot the instance once complete, usually in about 3-5 minutes.

${green}[DEBUG]${reset} For ${blue}windows${reset} instances: Please create your password ${blue}gcloud compute reset-windows-password ${gcp_name}-X[--zone ${gcp_zone}]${reset}
  ${green}[DEBUG]${reset} Please open powershell(non-admin) and run the following lines to install mobaxterm/firefox/powertoys/other tools:
  ${blue}[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12${reset}
  ${blue}iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/jlim0930/scripts/master/gcp-postinstall.ps1'))${reset}
EOF
}

## main body
case ${1} in
  create|start)
    find_instances
    create_instances
    ;;
  find|info|status|check)
    find_instances
    ;;
  delete|cleanup|stop)
    delete_instances
    ;;
  *)
    help
    ;;
esac


