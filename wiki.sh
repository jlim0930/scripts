#!/bin/sh

# this script will use the linuxserver's dokuwiki container and manage your content on a github repo

# Please create a github repo named wiki and set it to private.
# setup ssh keys for github for this script to work correctly


# Assumptions:
# 1 the wiki will be placed in your homedir/wiki
# 2 your container name will be wiki

# Please edit vars below
GHUSERNAME="jlim0930"
PORT="9090"

# colors
red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

# assign vars
userID=$(id -u)
groupID=$(id -g)
DATE=$(date +"%Y%m%d-%H%M")

# functions
bootstrap () {
    if [ ! -d ~/wiki ]; then
        echo "${green}[DEBUG]${reset} Creating ~/wiki"
        mkdir ~/wiki
        git clone git@github.com:${GHUSERNAME}/wiki.git ~/wiki
        if [ $? -ne 0 ]; then
          echo "${red}[DEBUG]${reset} Unable to clone from github. Exiting..."
          exit
        fi

    fi
}

gitpush () {
    cd ~/wiki
    if [ ! -f ~/wiki/.gitignore ]; then
      cat > ~/wiki/.gitignore<<EOF
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
    cd ~/wiki
    git reset --hard
    git pull --rebase
    if [ $? -ne 0 ]; then
      echo "${red}[DEBUG]${reset} Unable to pull from github"
    else
      docker restart wiki
    fi
}

containerstart () {
    if [ ! "$(docker ps -q -f name=wiki)" ]; then
      if [ "$(docker ps -aq -f status=exited -f name=wiki)" ]; then
        # cleanup
        docker rm wiki
      fi
      # run your container
      bootstrap
      docker run -d --name=wiki -e PUID=${userID} -e GUID=${groupID} -e TZ=America\Chicago -p ${PORT}:80 -v ~/wiki:/config --restart unless-stopped ghcr.io/linuxserver/dokuwiki
    fi
}

cleanup () {
    docker stop wiki
    docker rm wiki
    rm -rf ~/wiki
}


case $1 in
    bootstrap)
        bootstrap
        ;;
    push)
        gitpush
        ;;
    pull)
        gitpull
        ;;
    start)
        containerstart
        ;;
    stop)
        docker stop wiki
        ;;
    cleanup)
        cleanup
        ;;
    *)
        echo "${green}Usage:${reset} ./`basename $0` command"
#        echo "                 ${green}bootstrap${reset} - Create ~/wiki and git clone"
        echo "                 ${green}push${reset} - push contents to git repo"
        echo "                 ${green}pull${reset} - pull contents from git repo"
        echo "                 ${green}start${reset} - init and start container"
        echo "                 ${green}stop${reset} - stops wiki container"
        echo "                 ${green}cleanup${reset} - stops and removes container and ~/wiki"
        echo ""
        echo "Please make sure edit the editable section in the script"
        echo "Please create your github repo first"
        ;;
esac

