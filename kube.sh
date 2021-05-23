#!/usr/bin/env bash

# justin lim <justin@isthecoolest.ninja>

# $ curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/kube.sh -o kube.sh

# This script will have options to start up minikube or clean it up.
# options: start|stop|delete
# if minikube & kubectl is not installed it will automatically install it.
# will enable metallb and add IP pool with minikube ip network and pool of 150-175
# sudo access is required for some instances
# tested on linux and macOS
#
# for linux it will use the docker driver
# for macOS it will use the hyperkit driver
#################

## User configurable variables
CPU=""         # Please change this to the # of cores you want minikube to use. If not set it will use half of your total core count
MEM=""         # Please change this  to the amount of memory to give to minikube. If not set it will use half of your memory up to 16GB max
# HDD=""        # Please change this to the amount of hdd space to give for minikube. default is 20,000MB

## vars

# colors
red=`tput setaf 1`
green=`tput setaf 2`
blue=`tput setaf 4`
reset=`tput sgr0`

# Get OS & set CPU & MEM
OS=`uname -s`
case ${OS} in
  "Linux")
    OS="linux"
    if [ -z ${CPU} ]; then
      temp=`nproc`
      CPU=`echo "${temp}/2" | bc`
    fi
    if [ -z ${MEM} ]; then
      temp=`free -m | awk '/Mem\:/ { print $2 }'`
      value=`echo "${temp}/2" | bc`
      if [ ${value} -gt "16384" ]; then
        MEM="16384"
      else
        MEM="${value}"
      fi
    fi
    ;;
  "Darwin")
    if [ `uname -m` == "x86_64" ]; then
      OS="macos-x86_64"
    elif [ `uname -m` == "arm64" ]; then
      OS="macos-arm64"
    fi
    if [ -z ${CPU} ]; then
      temp=`sysctl -n hw.ncpu`
      CPU=`echo "${temp}/2" | bc`
    fi
    if [ -z ${MEM} ]; then
      temp=`sysctl -n hw.memsize`
      value=`echo "${temp}/2097152" | bc`
      if [ ${value} -gt "16384" ]; then
        MEM="16384"
      else
        MEM="${value}"
      fi
    fi
    ;;
  *)
    echo "${red}[DEBUG]${reset} This script only supports macOS and linux"
    exit
    ;;
esac

## functions

# function help
function help() {
  echo -e "${green}Usage:{$reset} ./`basename $0` [start|stop|delete]"
  exit
}

# function check and install minikube
function checkminikube() {
  if ! [ -x "$(command -v minikube)" ]; then
    echo "${red}[DEBUG]${reset} minikube not found. Installing."
    if [ $OS == "linux" ]; then
      echo "${green}[DEBUG]${reset} Linux found."
      curl -LO -s https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
      sudo install minikube-linux-amd64 /usr/local/bin/minikube
      rm -rf minikube-linux-amd64 >/dev/null 2>&1
    elif [ ${OS} == "macos-x86_64" ]; then
      echo "${gree}[DEBUG]${reset} macOS x86_64 found."
      curl -LO -s https://storage.googleapis.com/minikube/releases/latest/minikube-darwin-amd64
      sudo install minikube-darwin-amd64 /usr/local/bin/minikube
      rm -rf minikube-darwin-amd64 >/dev/null 2>&1
    elif [ ${OS} == "macos-arm64" ]; then
      echo "${green}[DEBUG]${reset} macOS arm64 found."
      curl -LO -s https://storage.googleapis.com/minikube/releases/latest/minikube-darwin-arm64
      sudo install minikube-darwin-arm64 /usr/local/bin/minikube
      rm -rf minikube-darwin-arm64 >/dev/null 2>&1
    fi
  else
    echo "${green}[DEBUG]${reset} minikube found."
  fi
}

# function check and install kubectl
function checkkubectl() {
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
}

# function check docker
function checkdocker() {
  if [ ${OS} == "macos-x86_64" ] || [ ${OS} == "macos-arm64" ]; then
    echo "${green}[DEBUG]${reset} macos found will use hyperkit instead of docker"
  else
    docker info >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo "${red}[DEBUG]${reset} Docker is not running or installed or your not part of the docker group.  Please fix"
      exit
    fi
  fi
}

# function start
function build() {
  echo "${green}[DEBUG]${reset} CPU will be set to ${CPU} cores"
  minikube config set cpus ${CPU}
  echo "${green}[DEBUG]${reset} MEM will be set to ${MEM}mb"
  minikube config set memory ${MEM}
#  minikube config set disk-size ${HDD}
  if [ ${OS} == "linux" ]; then
    minikube start --driver=docker
  else
    minikube start --driver=hyperkit
  fi
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


