#!/bin/bash

# ===== User Configurable Variables =====
gke_project="elastic-support-k8s-dev"
gke_region="us-central1"
gke_machine_type="e2-standard-4"
label="division=support,org=support,team=support,project=${gke_cluster_name}"

gke_cluster_nodes="1"

# ===== Constants =====
gke_cluster_name="$(whoami | sed $'s/[^[:alnum:]\t]//g')-gkelab"
kubectl_url_base="https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin"
kubectl_install_path="/usr/local/bin/kubectl"

# ===== Color Constants =====
red=$(tput setaf 1)
green=$(tput setaf 2)
blue=$(tput setaf 4)
reset=$(tput sgr0)

# ===== Helper Functions =====
help() {
  echo "This script is to stand up a GKE environment in ${gke_project}"
  echo ""
  echo "${green}Usage:${reset} ./$(basename $0) COMMAND"
  echo "${blue}COMMANDS${reset}"
  echo "  ${green}start${reset} - Starts your GKE environment"
  echo "  ${green}find${reset}  - Searches for your deployment"
  echo "  ${green}delete${reset} - Deletes your GKE environment"
}

checkkubectl() {
  if ! command -v kubectl &>/dev/null; then
    echo "${red}[DEBUG]${reset} kubectl not found. Installing."
    case ${OS} in
      "linux")
        curl -LO "${kubectl_url_base}/linux/amd64/kubectl"
        ;;
      "macos-x86_64")
        curl -LO "${kubectl_url_base}/darwin/amd64/kubectl"
        ;;
      "macos-arm64")
        curl -LO "${kubectl_url_base}/darwin/arm64/kubectl"
        ;;
    esac
    sudo install kubectl "${kubectl_install_path}"
    rm -f kubectl
  else
    echo "${green}[DEBUG]${reset} kubectl found."
  fi
}

find_cluster() {
  if gcloud container clusters list --project "${gke_project}" 2> /dev/null| grep -q "${gke_cluster_name}"; then
    echo "${green}[DEBUG]${reset} Cluster ${gke_cluster_name} exists."
    echo ""
    gcloud container clusters list --project "${gke_project}" 2> /dev/null| grep -E "STATUS|${gke_cluster_name}"
  else
    echo "${red}[DEBUG]${reset} Cluster ${gke_cluster_name} not found."
  fi
}

start_cluster() {
  find_cluster
  echo "${green}[DEBUG]${reset} Creating cluster ${gke_cluster_name}"
  echo ""

  gcloud container clusters create "${gke_cluster_name}" \
    --labels="${label}" \
    --project="${gke_project}" \
    --region="${gke_region}" \
    --num-nodes="${gke_cluster_nodes}" \
    --machine-type="${gke_machine_type}" \
    --disk-type="pd-ssd" \
    --disk-size="100" \
    --image-type="COS_CONTAINERD" \
    --release-channel="stable" \
    --max-pods-per-node="110" \
    --cluster-ipv4-cidr="/17" \
    --services-ipv4-cidr="/22" \
    --enable-ip-alias \
    --enable-autorepair

  echo "${green}[DEBUG]${reset} Configuring kubectl context for ${gke_cluster_name}"
  gcloud container clusters get-credentials "${gke_cluster_name}" --region="${gke_region}" --project="${gke_project}"

  echo "${green}[DEBUG]${reset} Adding gcloud RBAC for cluster admin role"
  kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin \
    --user="$(gcloud auth list --filter=status:ACTIVE --format="value(account)")"
}

delete_cluster() {
  if gcloud container clusters list --project "${gke_project}" 2> /dev/null| grep -q "${gke_cluster_name}"; then
    echo "${green}[DEBUG]${reset} Removing kubectl context"
    kubectl config unset current-context
    kubectl config delete-context "gke_${gke_project}_${gke_region}_${gke_cluster_name}"

    echo "${green}[DEBUG]${reset} Deleting ${gke_cluster_name}"
    gcloud container clusters delete "${gke_cluster_name}" --project="${gke_project}" --region="${gke_region}" --quiet
  else
    echo "${red}[DEBUG]${reset} Cluster ${gke_cluster_name} not found"
  fi
}

# ===== Main Script =====
OS=$(uname -s)
case ${OS} in
  "Linux")
    OS="linux"
    ;;
  "Darwin")
    OS="macos-$(uname -m)"
    ;;
  *)
    echo "${red}[DEBUG]${reset} This script only supports macOS and Linux"
    exit 1
    ;;
esac

case ${1} in
  start|deploy|create)
    checkkubectl
    start_cluster
    ;;
  find|check|info|status)
    find_cluster
    ;;
  delete|cleanup|stop)
    delete_cluster
    ;;
  *)
    help
    exit 1
    ;;
esac
