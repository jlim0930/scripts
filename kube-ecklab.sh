#!/bin/bash

# justin lim <justin@isthecoolest.ninja>

# $ curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/kube.sh -o kube.sh

# This script will have options to start up minikube or clean it up.
# options: start|stop|delete
# if minikube & kubectl is not installed it will automatically install it.
# will enable metallb and add IP pool with minikube ip network and pool of 150-175
# sudo access is required for some instances
# tested on linux and macOS
#

#################

## User configurable variables
CPU=""         # Please change this to the # of cores you want minikube to use. If not set it will use half of your total core count
MEM=""         # Please change this  to the amount of memory to give to minikube. If not set it will use half of your memory up to 16GB max
# HDD=""        # Please change this to the amount of hdd space to give for minikube. default is 20,000MB

VERSION="v1.33.0"

SHELL=`env | grep SHELL | awk -F"/" '{ print $NF }'`

## vars

# colors
red=`tput setaf 1`
green=`tput setaf 2`
blue=`tput setaf 4`
reset=`tput sgr0`

# if root exit
if [ `id -u` -eq 0 ]; then
  echo "${red}[DEBUG]${reset}Please do not run as root"
  exit
fi

# set CPU
if [ -z ${CPU} ]; then
  temp=`nproc`
  CPU=`echo $((${temp}-1))`
fi

# set MEM
if [ -z ${MEM} ]; then
  temp=`free -m | grep Mem | awk {' print $2 '}`
  value=`echo $((${temp}-4096))`
  if [ ${value} -gt "16384" ]; then
    MEM="16384"
  else
    MEM="${value}"
  fi
fi


## functions

# function help
function help() {
  echo -e "${green}Usage:{$reset} ./`basename $0` [start|stop|delete]"
  exit
}

# function check and install minikube
function checkminikube() {
  if ! { [ -x "$(command -v minikube)" ] && [ `minikube version | grep version | awk {' print $3 '}` = "${VERSION}" ]; } then
    echo "${red}[DEBUG]${reset} minikube not found or wrong version. Installing."
    curl -LO -s https://storage.googleapis.com/minikube/releases/${VERSION}/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm -rf minikube-linux-amd64 >/dev/null 2>&1
  else
    echo "${green}[DEBUG]${reset} minikube found."
  fi
}

# function check and install kubectl
function checkkubectl() {
  if ! [ -x "$(command -v kubectl)" ]; then
    echo "${red}[DEBUG]${reset} kubectl not found. Installing."
    curl -LO -s "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install kubectl /usr/local/bin/kubectl
    rm -rf kubectl >/dev/null 2>&1
  else
    echo "${green}[DEBUG]${reset} kubectl found."
  fi
}

# function delete the local minikube and kubectl in /usr/local/bin
function deletemk() {
#  if [ -x "$(command -v kubectl)" ]; then
#    rm -rf $(command -v kubectl)
#    echo "${green}[DEBUG]${reset} Deleted kubectl"
#  fi
  if [ -x "$(command -v minikube)" ]; then
    rm -rf $(command -v minikube)
    echo "${green}[DEBUG]${reset} Deleted minikube"
  fi
}

# function check docker
function checkdocker() {
  docker info >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${red}[DEBUG]${reset} Docker is not running or installed or your not part of the docker group.  Please fix"
    exit
  fi
}

# function start
function build() {
  echo "${green}[DEBUG]${reset} CPU will be set to ${CPU} cores"
  minikube config set cpus ${CPU}
  echo "${green}[DEBUG]${reset} MEM will be set to ${MEM}mb"
  minikube config set memory ${MEM}

  # adding host entries onto the host
  echo "192.168.49.175 kibana.eck.lab" > /etc/hosts
  # adding host entries for minikube
  mkdir -p ~/.minikube/files/etc
  echo "127.0.0.1 localhost" > ~/.minikube/files/etc/hosts
  echo "192.168.49.175 kibana.eck.lab" >> ~/.minikube/files/etc/hosts

  minikube start --driver=docker
  minikube addons enable metallb
  baseip=`minikube ip | cut -d"." -f1-3`
  startip="${baseip}.150"
  endip="${baseip}.175"
  cat > /tmp/metallb-config.yaml <<EOF
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

  kubectl apply -f /tmp/metallb-config.yaml >/dev/null 2>&1
  rm -rf /tmp/metallb-config.yaml >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} minikube IP is: `minikube ip`"
  echo "${green}[DEBUG]${reset} LoadBalancer Pool: ${startip} - ${endip}"

}

## script

case ${1} in
  build|start)
    checkminikube
    checkkubectl
    checkdocker
    echo "${green}[DEBUG]${reset} build minikube"
    build
    ;;
  stop)
    echo "${green}[DEBUG]${reset} Stopping minikube"
    minikube stop
    ;;
  upgrade)
    deletemk
    checkminikube
    checkkubectl
    echo "${green}[DEBUG]${reset} minikube and kubectl upgraded"
    ;;
  delete|cleanup)
    echo "${green}[DEBUG]${reset} Deleting minikube"
    minikube delete
    rm -rf ${HOME}/.minikube >/dev/null 2>&1
    rm -rf ${HOME}/.kube >/dev/null 2>&1
    ;;
  *)
    help
    ;;
esac
