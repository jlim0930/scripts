#!/usr/bin/env bash

# justin lim <justin@isthecoolest.ninja>

# $ curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/kube.sh -o kube.sh

# This script will have options to start up minikube or clean it up.
# options: start|stop|upgrade|delete
# if minikube & kubectl is not installed (or not the latest compatible release) it will automatically install it.
#   minikube : always the latest release
#   kubectl  : any version within +/-1 minor of K8S_MINOR is kept; otherwise the latest patch of K8S_MINOR+1 is installed
#   k8s      : always the latest patch of K8S_MINOR
# will enable metallb and add IP pool with minikube ip network and pool of 150-175
# sudo access is required for some instances
# tested on linux and macOS
#

#################

set -euo pipefail

## User configurable variables
CPU="${CPU:-}"                     # Number of cores for minikube. If not set: total cores - 1
MEM="${MEM:-}"                     # Memory (MB) for minikube. If not set: total memory - 4096MB, 16384MB max
# HDD=""                           # hdd space for minikube. default is 20,000MB

K8S_MINOR="1.31"                   # Kubernetes minor version minikube will run
KUBECTL_MINOR="${KUBECTL_MINOR:-1.$((${K8S_MINOR#*.} + 1))}"  # kubectl minor to install when needed: K8S_MINOR+1 (newest within +/-1 skew)
LOCAL_PATH_VERSION="v0.0.37"       # rancher local-path-provisioner release
DATA_DIR="/u01"                    # Host directory mounted into minikube and used by the pd-ssd StorageClass
POOL_START=150                     # MetalLB pool start (last octet of the minikube network)
POOL_END=175                       # MetalLB pool end

## vars
BIN_DIR="/usr/local/bin"
WORKDIR=""
OS=""
ARCH=""

# colors (only when attached to a terminal)
red="" green="" reset=""
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  red=$(tput setaf 1 2>/dev/null || true)
  green=$(tput setaf 2 2>/dev/null || true)
  reset=$(tput sgr0 2>/dev/null || true)
fi

## functions

info() { printf '%s[DEBUG]%s %s\n' "${green}" "${reset}" "$*"; }
err() { printf '%s[DEBUG]%s %s\n' "${red}" "${reset}" "$*" >&2; }
die() { err "$*"; exit 1; }

cleanup() {
  if [[ -n "${WORKDIR}" ]]; then
    rm -rf "${WORKDIR}"
  fi
}
trap cleanup EXIT

# function help
usage() {
  printf '%sUsage:%s ./%s [start|stop|upgrade|delete]\n' "${green}" "${reset}" "$(basename "$0")"
}

# detect OS and architecture
detect_platform() {
  case "$(uname -s)" in
    Linux) OS="linux" ;;
    Darwin) OS="darwin" ;;
    *) die "Unsupported OS: $(uname -s)" ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) ARCH="amd64" ;;
    aarch64 | arm64) ARCH="arm64" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}

# set CPU and MEM if the user did not
set_resources() {
  local total_cpu total_mem
  if [[ -z "${CPU}" ]]; then
    if [[ "${OS}" == "darwin" ]]; then
      total_cpu=$(sysctl -n hw.ncpu)
    else
      total_cpu=$(nproc)
    fi
    CPU=$((total_cpu - 1))
    if ((CPU < 2)); then CPU=2; fi
  fi

  if [[ -z "${MEM}" ]]; then
    if [[ "${OS}" == "darwin" ]]; then
      total_mem=$(($(sysctl -n hw.memsize) / 1024 / 1024))
    else
      total_mem=$(free -m | awk '/^Mem:/ {print $2}')
    fi
    MEM=$((total_mem - 4096))
    if ((MEM > 16384)); then MEM=16384; fi
    if ((MEM < 2200)); then MEM=2200; fi
  fi
}

# run a command as root only when needed
as_root() {
  if [[ -w "${BIN_DIR}" ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# download <url> to <dest> and verify it against <url>.sha256
download_verify() {
  local url=$1 dest=$2 expected actual
  curl -fsSL "${url}" -o "${dest}"
  expected=$(curl -fsSL "${url}.sha256" | awk '{print $1}')
  actual=$(sha256_of "${dest}")
  if [[ -z "${expected}" || "${expected}" != "${actual}" ]]; then
    die "Checksum mismatch for ${url}"
  fi
}

# install <src> as ${BIN_DIR}/<name>
install_bin() {
  local src=$1 name=$2
  as_root install -d "${BIN_DIR}"
  as_root install -m 0755 "${src}" "${BIN_DIR}/${name}"
  hash -r
  if [[ "$(command -v "${name}")" != "${BIN_DIR}/${name}" ]]; then
    err "${name} on PATH is $(command -v "${name}"), which shadows ${BIN_DIR}/${name}"
  fi
}

# latest published versions
latest_minikube_version() {
  curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/kubernetes/minikube/releases/latest | sed 's#.*/##'
}
latest_k8s_patch() { # <minor> e.g. 1.31 -> v1.31.14
  curl -fsSL "https://dl.k8s.io/release/stable-$1.txt"
}

# function check and install minikube
checkminikube() {
  local want have=""
  want=$(latest_minikube_version)
  [[ -n "${want}" ]] || die "Unable to determine the latest minikube version"
  if command -v minikube >/dev/null 2>&1; then
    have=$(minikube version --short 2>/dev/null || true)
  fi
  if [[ "${have}" == "${want}" ]]; then
    info "minikube ${have} found."
    return 0
  fi
  info "minikube ${have:-not found}; installing ${want}."
  [[ -n "${WORKDIR}" ]] || WORKDIR=$(mktemp -d)
  download_verify "https://storage.googleapis.com/minikube/releases/${want}/minikube-${OS}-${ARCH}" "${WORKDIR}/minikube"
  install_bin "${WORKDIR}/minikube" minikube
}

# function check and install kubectl
checkkubectl() {
  local want have="" have_minor diff
  if command -v kubectl >/dev/null 2>&1; then
    have=$(kubectl version --client 2>/dev/null | awk '/Client Version/ {print $3}' || true)
  fi
  # keep any kubectl that is within +/-1 minor of the Kubernetes version
  have_minor=${have#v1.}
  have_minor=${have_minor%%.*}
  if [[ "${have_minor}" =~ ^[0-9]+$ ]]; then
    diff=$((have_minor - ${K8S_MINOR#*.}))
    if ((diff >= -1 && diff <= 1)); then
      info "kubectl ${have} found (within +/-1 minor of Kubernetes ${K8S_MINOR})."
      return 0
    fi
  fi
  want=$(latest_k8s_patch "${KUBECTL_MINOR}")
  [[ -n "${want}" ]] || die "Unable to determine the latest kubectl ${KUBECTL_MINOR} version"
  if [[ -n "${have}" ]]; then
    info "kubectl ${have} is not within +/-1 minor of Kubernetes ${K8S_MINOR}; installing ${want}."
  else
    info "kubectl not found; installing ${want}."
  fi
  [[ -n "${WORKDIR}" ]] || WORKDIR=$(mktemp -d)
  download_verify "https://dl.k8s.io/release/${want}/bin/${OS}/${ARCH}/kubectl" "${WORKDIR}/kubectl"
  install_bin "${WORKDIR}/kubectl" kubectl
}

# function check docker
checkdocker() {
  if ! docker info >/dev/null 2>&1; then
    die "Docker is not running or installed or you're not part of the docker group. Please fix"
  fi
}

# function check other tools
checktools() {
  local tool
  for tool in curl jq awk sed; do
    command -v "${tool}" >/dev/null 2>&1 || die "${tool} is required but not installed"
  done
}

# make sure the host data dir exists
checkdatadir() {
  if [[ ! -d "${DATA_DIR}" ]]; then
    info "Creating ${DATA_DIR}"
    sudo mkdir -p "${DATA_DIR}" || die "Unable to create ${DATA_DIR}; create it manually or change DATA_DIR"
    sudo chown "$(id -u):$(id -g)" "${DATA_DIR}"
  fi
}

# retry <timeout-seconds> <command...> until it succeeds
wait_for() {
  local timeout=$1 i
  shift
  for ((i = 0; i < timeout; i += 2)); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  return 1
}

# replace the default storage class with a csi-hostpath backed "standard" supporting expansion
fix_storageclass() {
  info "Fixing storageClass"
  minikube addons disable default-storageclass >/dev/null 2>&1 || true
  minikube addons enable volumesnapshots >/dev/null
  minikube addons enable csi-hostpath-driver >/dev/null
  wait_for 120 kubectl get storageclass csi-hostpath-sc || die "csi-hostpath-sc was not created"
  kubectl delete storageclass standard --ignore-not-found >/dev/null
  kubectl get storageclass csi-hostpath-sc -o json | jq '
    del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp,
        .metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]) |
    .metadata.name = "standard" |
    .metadata.annotations["storageclass.kubernetes.io/is-default-class"] = "true" |
    .allowVolumeExpansion = true
  ' | kubectl apply -f -
  kubectl delete storageclass csi-hostpath-sc
}

# setup pd-ssd storageclass backed by DATA_DIR
setup_pdssd() {
  info "Setting up pd-ssd StorageClass backed by ${DATA_DIR}"
  kubectl apply -f "https://raw.githubusercontent.com/rancher/local-path-provisioner/${LOCAL_PATH_VERSION}/deploy/local-path-storage.yaml" >/dev/null
  kubectl delete storageclass local-path --ignore-not-found >/dev/null
  kubectl -n local-path-storage patch configmap local-path-config --type merge -p "$(
    jq -nc --arg p "${DATA_DIR}" \
      '{data: {"config.json": ({nodePathMap: [{node: "DEFAULT_PATH_FOR_NON_LISTED_NODES", paths: [$p]}]} | tojson)}}'
  )" >/dev/null
  kubectl apply -f - >/dev/null <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: pd-ssd
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
  info "pd-ssd StorageClass created"
}

# enable metallb with a pool on the minikube network
setup_metallb() {
  local ip baseip startip endip
  minikube addons enable metallb
  ip=$(minikube ip)
  baseip=${ip%.*}
  startip="${baseip}.${POOL_START}"
  endip="${baseip}.${POOL_END}"
  kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - ${startip}-${endip}
EOF
  info "minikube IP is: ${ip}"
  info "LoadBalancer Pool: ${startip} - ${endip}"
}

# function start
build() {
  local k8s_version
  k8s_version=$(latest_k8s_patch "${K8S_MINOR}")
  [[ -n "${k8s_version}" ]] || die "Unable to determine the latest Kubernetes ${K8S_MINOR} version"

  info "Kubernetes will be ${k8s_version}"
  info "CPU will be set to ${CPU} cores"
  minikube config set cpus "${CPU}"
  info "MEM will be set to ${MEM}mb"
  minikube config set memory "${MEM}"

  # adding host entries for minikube
  mkdir -p "${HOME}/.minikube/files/etc"
  printf '%s\n' "127.0.0.1 localhost" "192.168.49.170 kibana.eck.lab" >"${HOME}/.minikube/files/etc/hosts"

  minikube start --driver=docker --kubernetes-version="${k8s_version}" \
    --mount --mount-string="${DATA_DIR}:${DATA_DIR}"

  fix_storageclass
  setup_pdssd
  setup_metallb
}

main() {
  case "${1:-}" in
    build | start)
      [[ "$(id -u)" -ne 0 ]] || die "Please do not run as root"
      detect_platform
      set_resources
      checktools
      checkminikube
      checkkubectl
      checkdocker
      checkdatadir
      info "build minikube"
      build
      ;;
    stop)
      info "Stopping minikube"
      minikube stop
      ;;
    upgrade)
      detect_platform
      checktools
      checkminikube
      checkkubectl
      info "minikube and kubectl are u
                                      p to date"
      ;;
    delete | cleanup)
      info "Deleting minikube"
      if command -v minikube >/dev/null 2>&1; then
        minikube delete
      fi
      rm -rf -- "${HOME}/.minikube" "${HOME}/.kube"
      ;;
    -h | --help | help)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

# only run when executed, not when sourced (lets the functions be tested)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
