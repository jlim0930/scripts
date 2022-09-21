#!/bin/bash

## Creates a GKE cluster
# ------- EDIT information below to customize for your needs
gke_cluster_name="justinlim-gke"          # name of your k8s cluster
gke_project="xxxxxxxxxxxxxxxx"     # project that you are linked to

#gke_zone="us-central1-c"                  # zone
gke_region="us-central1"                  # region
gke_cluster_nodes="1"                     # number of cluster
gke_machine_type="e2-standard-4"          # node machine type
# gke_cluster_node_vCPUs="4"               # vCPUs for node
# gke_cluster_node_RAM="16384"

# -------- do not edit below

# colors
red=`tput setaf 1`
green=`tput setaf 2`
blue=`tput setaf 4`
reset=`tput sgr0`


# help function
help() {
  echo "This script is to stand up a GKE environment in ${gke_project}"
  echo ""
  echo "${green}Usage:${reset} ./`basename $0` COMMAND"
  echo "${blue}COMMANDS${reset}"
  echo "  ${green}start${reset} - Starts your GKE environment"
  echo "  ${green}find${reset} - Searchs for your deployment"
  echo "  ${green}delete${reset} - Deletes your GKE environment"

} # end help

# check for kubectl and install it - will need sudo
checkkubectl() {
  if ! [ -x "$(command -v kubectl)" ]; then
    echo "${red}[DEBUG]${reset} kubectl not found. Installing."
    if [ $OS == "linux" ]; then
      echo "${green}[DEBUG]${reset} Linux found."
      curl -LO -s "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
      sudo install kubectl /usr/local/bin/kubectl
      rm -rf kubectl >/dev/null 2>&1
    elif [ ${OS} == "macos-x86_64" ]; then
      echo "${gree}[DEBUG]${reset} macOS x86_64 found."
       curl -LO -s "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
      sudo install kubectl /usr/local/bin/kubectl
      rm -rf kubectl >/dev/null 2>&1
    elif [ ${OS} == "macos-arm64" ]; then
      echo "${gree}[DEBUG]${reset} macOS arm64 found."
      curl -LO -s "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/arm64/kubectl"
      sudo install kubectl /usr/local/bin/kubectl
      rm -rf kubectl >/dev/null 2>&1
    fi
  else
    echo "${green}[DEBUG]${reset} kubectl found."
  fi
} # end checkkubectl

# find function
find() {
  if [ $(gcloud container clusters list 2> /dev/null --project ${gke_project} |  grep ${gke_cluster_name} | wc -l) -gt 0 ]; then
    echo "${green}[DEBUG]${reset} Cluster ${gke_cluster_name} exists."
    echo ""
    gcloud container clusters list --project ${gke_project} | egrep "STATUS|${gke_cluster_name}"
    exit
  else
    echo "${green}[DEBUG]${reset} Cluster ${gke_cluster_name} not found."
  fi    
} # end find

# start the deloyment
start() {
  find
  echo "${green}[DEBUG]${reset} Creating cluster ${gke_cluster_name}"
  echo ""

#  gcloud container clusters create ${gke_cluster_name} --project ${gke_project} --region ${gke_region} --num-nodes=${gke_cluster_nodes} --machine-type=${gke_machine_type} --image-type="COS_CONTAINERD"
  gcloud container clusters create ${gke_cluster_name} \
	  --project ${gke_project} \
	  --region ${gke_region} \
	  --num-nodes=${gke_cluster_nodes} \
	  --machine-type=${gke_machine_type} \
	  --disk-type=pd-ssd \
	  --image-type="COS_CONTAINERD" \
	  --release-channel stable \
	  --enable-autoscaling --min-nodes "0" --max-nodes "3"

  echo ""
  echo "${green}[DEBUG]${reset} Configure kubectl context for ${gke_cluster_name}"
  gcloud container clusters get-credentials ${gke_cluster_name} --region ${gke_region}  --project ${gke_project}

  echo "${green}[DEBUG]${reset} Adding gcloud RBAC for cluster admin role"
  kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
} # end start

# delete | cleanup
delete() {
  if [ $(gcloud container clusters list 2> /dev/null --project ${gke_project} | grep ${gke_cluster_name} | wc -l) -gt 0 ]; then
    echo "${green}[DEBUG]${reset} Deleting ${gke_cluster_name}"
    gcloud container clusters delete ${gke_cluster_name} --project ${gke_project} --region ${gke_region} --quiet;

    echo "${green}[DEBUG]${reset} Remove kubectl context"
    kubectl config unset contexts.${gke_cluster_name}
  else 
    echo "${red}[DEBUG]${reset} Cluster ${gke_cluster_name} not found"
  fi
} # end delete

OS=`uname -s`
case ${OS} in
  "Linux")
    OS="linux"
    ;;
  "Darwin")
    if [ `uname -m` == "x86_64" ]; then
      OS="macos-x86_64"
    elif [ `uname -m` == "arm64" ]; then
      OS="macos-arm64"
    fi
    ;;
  *)
    echo "${red}[DEBUG]${reset} This script only supports macOS and linux"
    exit
    ;;
esac

case ${1} in
  deploy|start)
    checkkubectl
    start
    ;;
  find|check|info|status)
    find
    ;;
  cleanup|delete|stop)
    delete
    ;;
  *)
    help
    exit
    ;;
esac
