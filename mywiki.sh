#!/usr/bin/env bash

# This script will use linuxserver.io dokuwiki container and manage your content on github repo

# Please create a github repo named wiki and set it to private
# https://docs.github.com/en/github/getting-started-with-github/create-a-repo
# setup ssh keys for github so that this script can use it to get/push content
# https://docs.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh


# This script will create ${HOME}/wiki to store your content
# Container name will be wiki

# Editable variables
GHUSERNAME="<GITHUB USERNAME>"
PORT="9090"
TLSPORT="9091"

# colors
red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

# assign vars
userID=$(id -u)
groupID=$(id -g)
DATE=$(date +"%Y%m%d-%H%M")

# functions
build() {
  #
  if [ ! -d ${HOME}/wiki ]; then
    echo "${green}[DEBUG]${reset} Creating ${HOME}/wiki"
    mkdir -p ${HOME}/wiki > /dev/null 2>&1
    git clone git@github.com:${GHUSERNAME}/wiki.git ${HOME}/wiki
    if [ $? -ne 0 ]; then
      echo "${red}[DEBUG]${reset} Unable to clone from github.  Exiting...."
      exit
    fi
# decided this isnt needed
#  else
#    echo "${green}[DEBUG]${reset} ${HOME}/wiki already exists.. will create the container"
  fi
  if [ $(docker ps | grep -c wiki) -ge 1 ]; then
    echo "${green}[DEBUG]${reset} wiki container is already running"
  elif [ $(docker ps -a | grep -c wiki) -ge 1 ]; then
    echo "${green}[DEBUG]${reset} wiki container exits but is not running. Starting container"
    docker start wiki >/dev/null 2>&1
  elif [ $(docker ps -a | grep -c wiki) -eq 0 ]; then
    echo "${green}[DEBUG]${reset} Creating wiki container"
    docker run -d --name=wiki -e PUID=${userID} -e GUID=${groupID} -e TZ=America\Chicago -p ${PORT}:80 -p ${TLSPORT}:443 -v ${HOME}/wiki:/config --restart unless-stopped ghcr.io/linuxserver/dokuwiki >/dev/null 2>&1
  fi
}

stopcontainer() {
  if [ $(docker ps -a | grep -c wiki) -ge 1 ]; then
    echo "${green}[DEBUG]${reset} Stopping wiki container"
    docker stop wiki >/dev/null 2>&1
  else
    echo "${red}[DEBUG]${reset} container is not running.  Nothing to stop"
  fi
}

gitpush () {
  if [ ! -d ${HOME}/wiki ]; then
    echo "${red}[DEBUG]${reset} ${HOME}/wiki does not exist so nothing to push."
    exit
  fi
  cd ${HOME}/wiki
  if [ ! -f ${HOME}/wiki/.gitignore ]; then
    cat > ${HOME}/wiki/.gitignore<<EOF
log/*/*.log
EOF
  fi
  git add .
  git commit -m "wiki updated ${DATE}"
  git branch -M main
  git push -u origin main
  if [ $? -ne 0 ]; then
    echo "${red}[DEBUG]${reset} Unable to push to github"
  fi
 }

gitpull () {
  build
  cd ${HOME}/wiki
  git reset --hard
  git pull --rebase
  if [ $? -ne 0 ]; then
    echo "${red}[DEBUG]${reset} Unable to pull from github"
  else
    docker restart wiki >/dev/null 2>&1
  fi
 }

cleanup() {
  echo "${green}[DEBUG]${reset} Stopping container"
  docker stop wiki >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} Removing container"
  docker rm wiki >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} Removing ${HOME}/wiki directory"
  rm -rf ${HOME}/wiki
}

case $1 in
  build)
    build
    ;;
  start)
    build
    ;;
  pull)
    gitpull
    ;;
  push)
    gitpush
    ;;
  stop)
    stopcontainer
    ;;
  cleanup)
    cleanup
    ;;
  *)
    echo "${green}Usage:${reset} ./`basename $0` command"
    echo "                 ${green}build${reset}   - Create ${HOME}/wiki and git clone"
    echo "                 ${green}push${reset}    - push contents to git repo"
    echo "                 ${green}pull${reset}    - pull contents from git repo"
    echo "                 ${green}start${reset}   - init and start container"
    echo "                 ${green}stop${reset}    - stops wiki container"
    echo "                 ${green}cleanup${reset} - stops and removes container and ${HOME}/wiki"
    echo ""
    echo "Please make sure edit the editable section in the script"
    echo "Please create your github repo first"
    ;;
esac
