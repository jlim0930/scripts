#!/usr/bin/env bash

## Creates GCP instances

# -------------- EDIT information below

### PERSONAL ###################
gcp_name="$(whoami | tr -cd '[:alnum:]')-ecklab"  # username (special chars stripped) + -ecklab
gcp_zone="us-central1-b"                           # GCP zone

### ORGANIZATION ###############
gcp_project="elastic-support"
machine_type="e2-standard-8"    # gcloud compute machine-types list
boot_disk_type="pd-ssd"         # gcloud compute disk-types list
label="division=support,org=support,team=support,project=${gcp_name}"

# -------- do not edit below

bold=$(tput bold)
red=$(tput setaf 1)
green=$(tput setaf 2)
blue=$(tput setaf 14)
reset=$(tput sgr0)

help() {
  echo "This script stands up a GCP environment in the ${gcp_project} project"
  echo ""
  echo "${green}Usage:${reset} ./$(basename "$0") COMMAND"
  echo "${blue}COMMANDS${reset}"
  echo "  ${green}create${reset} - Creates your GCP environment & runs post-install (rocky-linux-9-optimized-gcp)"
  echo "  ${green}find${reset}   - Finds info about your GCP environment"
  echo "  ${green}delete${reset} - Deletes your GCP environment"
}

gcp_find() {
  if gcloud compute instances list --project "${gcp_project}" 2>/dev/null | grep -q "${gcp_name}"; then
    echo "${green}[DEBUG]${reset} Instance(s) found"
    echo ""
    gcloud compute instances list --project "${gcp_project}" \
      --filter="name:${gcp_name}" \
      --format="table[box](name, zone.basename(), machineType.basename(), status, networkInterfaces[0].networkIP, networkInterfaces[0].accessConfigs[0].natIP, disks[0].licenses[0].basename())"
  else
    echo "${red}[DEBUG]${reset} You don't have any instances running"
  fi
}

delete() {
  if gcloud compute instances list --project "${gcp_project}" 2>/dev/null | grep -q "${gcp_name}"; then
    while IFS= read -r instance; do
      echo "${green}[DEBUG]${reset} Deleting ${instance}"
      gcloud compute instances delete "${instance}" --project "${gcp_project}" --zone="${gcp_zone}" --quiet
    done < <(gcloud compute instances list --project "${gcp_project}" | grep "${gcp_name}" | awk '{ print $1 }')
  else
    echo "${red}[DEBUG]${reset} Instance ${gcp_name} not found"
  fi
}

create() {
  echo "${green}[DEBUG]${reset} Creating instance ${blue}${gcp_name}${reset} (rocky-linux-9-optimized-gcp)"

  # shellcheck disable=SC2016
  gcloud compute instances create "${gcp_name}" \
    --quiet \
    --project "${gcp_project}" \
    --image-family rocky-linux-9-optimized-gcp \
    --image-project rocky-linux-cloud \
    --zone "${gcp_zone}" \
    --labels "${label}" \
    --machine-type "${machine_type}" \
    --tags=http-server,https-server \
    --create-disk="auto-delete=yes,boot=no,size=50,type=${boot_disk_type}" \
    --metadata=startup-script='#!/bin/sh
    if [ -b /dev/sdb ] && ! blkid /dev/sdb | grep -q xfs; then
      mkfs.xfs /dev/sdb
    fi
    if [ -b /dev/sdb ]; then
      mkdir -p /u01
      UUID=$(blkid -s UUID -o value /dev/sdb)
      if ! grep -q "$UUID" /etc/fstab; then
        echo "UUID=${UUID} /u01 xfs defaults 0 2" >> /etc/fstab
      fi
      mount /u01
    fi

    if [ -f /ran_startup ]; then
      exit 0
    fi

    cat >> /etc/hosts <<EOF
192.168.49.170 kibana.eck.lab
EOF

    cat > /etc/dnf/dnf.conf <<EOF
[main]
gpgcheck=1
installonly_limit=3
clean_requirements_on_remove=True
best=False
skip_if_unavailable=True
ip_resolve=4
fastestmirror=1
EOF

    yum clean all
    yum makecache

    yum install epel-release -y
    yum --enablerepo=extras install epel-release -y

    yum config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    yum install unzip bind-utils openssl vim-enhanced bash-completion git wget nmap bc jq net-tools kubectl docker-ce docker-ce-cli containerd.io -y

    for u in $(lid -g -n google-sudoers); do usermod -a -G docker $u; done
    systemctl daemon-reload
    systemctl enable docker
    systemctl start docker

    yum groupinstall base-x xfce-desktop -y
    yum install xrdp firefox -y
    echo "exec xfce4-session" >> /etc/xrdp/xrdp.ini
    systemctl daemon-reload
    systemctl enable xrdp
    systemctl start xrdp

    for service in auditd firewalld mdmonitor postfix bluetooth; do
      systemctl disable ${service}
    done

    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

    curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/deploy-elastick8s.sh -o /usr/local/bin/deploy-elastick8s.sh
    curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/kube-ecklab.sh -o /usr/local/bin/kube.sh
    chmod +x /usr/local/bin/*.sh

    yum update -y

    echo "done" > /ran_startup
    reboot
    '
  echo ""
  sleep 2
}

case ${1} in
  create|start)
    echo "${green}[DEBUG]${reset} rocky-linux-9-optimized-gcp starting on ${blue}${machine_type}${reset} in ${blue}${gcp_zone}${reset}"
    create
    echo ""
    echo "===================================================================================================================================="
    echo ""
    echo "${blue}[DEBUG]${reset} ${bold}Post-install is running and will reboot once complete (~3-5 minutes).${reset}"
    echo "${green}[DEBUG]${reset} Connect with: ${blue}gcloud compute ssh ${gcp_name} [--zone ${gcp_zone}]${reset}"
    echo ""
    ;;
  find|info|status|check)
    gcp_find
    ;;
  delete|cleanup|stop)
    delete
    ;;
  *)
    help
    ;;
esac
