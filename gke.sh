#!/bin/bash

# ===== User Configurable Variables =====
gke_project="elastic-support-k8s-dev"
gke_region="us-central1"
gke_machine_type="e2-standard-4"
label="division=support,org=support,team=support,project=gkelab"
gke_cluster_nodes="1"

# =======================================
gke_cluster_name="$(whoami | sed $'s/[^[:alnum:]\t]//g')-gkelab"
kubectl_url_base="https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin"
kubectl_install_path="/usr/local/bin/kubectl"

### colors
red=$(tput setaf 1)
green=$(tput setaf 2)
blue=$(tput setaf 14)
reset=$(tput sgr0)

# Function to display help
help() {
  cat << EOF
This script is to stand up a GKE environment in ${gcp_project} Project

${green}Usage:${reset} ./$(basename "$0") COMMAND
${blue}COMMANDS${reset}
  ${green}create|start|deploy${reset}      - Creates your GCP environment & runs post-scripts (Linux)
  ${green}find|check|info|status${reset}   - Finds info about your GCP environment
  ${green}delete|cleanup|stop${reset}      - Deletes your GCP environment
EOF
}

# Helper function to display debug messages
debug() {
  echo "${green}[DEBUG]${reset} $1"
}

debugr() {
  echo "${red}[DEBUG]${reset} $1"
}

checkkubectl() {
  if ! command -v kubectl &>/dev/null; then
    debugr "kubectl not found. Installing."
    case ${OS} in
      "linux")         os_path="linux/amd64" ;;
      "macos-x86_64")  os_path="darwin/amd64" ;;
      "macos-arm64")   os_path="darwin/arm64" ;;
      *)               echo "${red}[ERROR]${reset} Unsupported OS: ${OS}"; return 1 ;;
    esac

    # Download kubectl
    curl -LO "${kubectl_url_base}/${os_path}/kubectl"
    
    # Install kubectl and clean up
    sudo install kubectl "${kubectl_install_path}" && rm -f kubectl
  else
    debug "kubectl found."
  fi
}

find_cluster() {
  if gcloud container clusters list --project "${gke_project}" 2> /dev/null| grep -q "${gke_cluster_name}"; then
    debug "Cluster ${gke_cluster_name} exists."
    echo ""
    gcloud container clusters list --project "${gke_project}" 2> /dev/null| grep -E "STATUS|${gke_cluster_name}"
    exit
  else
    debugr "Cluster ${gke_cluster_name} not found."
  fi
}

start_cluster() {
  find_cluster
  debug "Creating cluster ${gke_cluster_name}"
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

  debug "Configuring kubectl context for ${gke_cluster_name}"
  gcloud container clusters get-credentials "${gke_cluster_name}" --region="${gke_region}" --project="${gke_project}"

  debug "Adding gcloud RBAC for cluster admin role"
  kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin \
    --user="$(gcloud auth list --filter=status:ACTIVE --format="value(account)")"
}

delete_cluster() {
  if gcloud container clusters list --project "${gke_project}" 2> /dev/null| grep -q "${gke_cluster_name}"; then
    debug "Removing kubectl context"
    kubectl config unset current-context
    kubectl config delete-context "gke_${gke_project}_${gke_region}_${gke_cluster_name}"

    debug "Deleting ${gke_cluster_name}"
    gcloud container clusters delete "${gke_cluster_name}" --project="${gke_project}" --region="${gke_region}" --quiet
  else
    debugr "Cluster ${gke_cluster_name} not found"
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
    debugr "This script only supports macOS and Linux"
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
