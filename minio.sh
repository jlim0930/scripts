#!/usr/bin/env bash

# min.io script to stand up docker-ized mini.io server on localhost and have the endpoint exposed as http://IP:9000
# will create a minio directory for the data directory.

# find IP
if [ "`uname -s`" != "Darwin" ]; then
  IP=`hostname -I | awk '{ print $1 }'`
else
  IP=`ifconfig | grep inet | grep -v inet6 | grep -v 127.0.0.1 | awk '{ print $2 }'`
fi

help() {
  echo -e "./`basename $0` command"
  echo -e "\tCOMMANDS"
  echo -e "\t\tbuild   - Fresh install - it will build a new minio docker instance named myminio"
  echo -e "\t\t\t\tmyminio directory will be created in your homedir"
  echo -e "\t\tstart   - Start myminio container if stopped"
  echo -e "\t\tstop    - Stop myminio container"
  echo -e "\t\tcleanup - Stops myminio container and delete it and delete ${HOME}/myminio"
}

checkdocker() {
  # check to ensure docker is running and you can run docker commands
  docker info >/dev/null 2>&1
  if [ $? -ne 0  ]; then
    echo "[DEBUG] Docker is not running or you are not part of the docker group"
    exit
  fi
}

makehome() {
  # check for minio directory and create if there is none.
  if [ -f ${HOME}/myminio ]; then
    mkdir -p ${HOME}/myminio
    echo "Created minio directory"
  fi
}

pullminio() {
  # checking for image - minio
  docker image inspect minio/minio:latest > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "[DEBUG] Pulling minio image.. might take a while"
    docker pull minio/minio:latest
  else
    echo "[DEBUG] Using existing minio image"
  fi
}

build() {
  makehome
  docker run -d -p 9000:9000 \
    --user $(id -u):$(id -g) \
    --name myminio \
    -e "MINIO_ROOT_USER=minio" \
    -e "MINIO_ROOT_PASSWORD=minio123" \
    -v ${HOME}/myminio:/data \
    minio/minio server /data
  if [ $? -eq 0 ]; then
    echo "[DEBUG] mmyinio started.  http://localhost:9000 or http://${IP}:9000.  access_key: minio  secret_key: minio123"
    echo ""
    echo "[DEBUG] Please visit https://dl.minio.io/client/mc/release/ and download the mc client for your machine and chmod a+x mc and place it in your path"
    echo "[DEBUG] Add myminio server into mc: mc config host add myminio http://127.0.0.1:9000 minio minio123"
    echo "[DEBUG] mc commands are located on https://dl.minio.io/client/mc/release/"
    echo "[DEBUG] For quick use:  Create Bucket: mc mb myminio/bucketname"
    echo "[DEBUG] You can use s3cmd as well."

  fi
}

start() {
  # check to see if container exists and if not build it and start it
  if [ "$(docker ps | grep -c myminio)" -eq 1 ]; then
    echo "[DEBUG] myminio is already running"
  elif [ "$(docker ps -a | grep -c myminio)" -eq 1 ]; then
    echo "[DEBUG] myminio found and starting container"
    docker start myminio
  else
    echo "[DEBUG] myminio container doesnt exist. Building"
    build
  fi
}

stop() {
  if [ "$(docker ps | grep myminio)" ]; then
    docker stop myminio
    echo "[DEBUG] Stopping myminio container"
  else
    echo "[DEBUG] myminio was not running"
  fi
}

cleanup() {
  stop
  if [ "$(docker ps -aq -f status=exited -f name=myminio)" ]; then
    docker rm myminio
  fi
  rm -rf ${HOME}/myminio
  echo "[DEBUG] Deleted ${HOME}/myminio"
}

# modes
case $1 in
  build)
    checkdocker
    build
    ;;
  start)
    checkdocker
    start
    ;;
  stop)
    stop
    ;;
  cleanup)
    cleanup
    ;;
  *)
    help
    ;;
esac
