#!/usr/bin/env bash


# justin lim <justin@isthecoolest.ninja>

# $ curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/deploy-elastic.sh -o deploy-elastic.sh
# $ sh ./deploy-elastic.sh {VERSION}
#
# Deploys 3 instances of ES into a cluster and 1 instance of kibana
# works for all 6.x 7.x versions
# Creates a directory of ${VERSION} on your current directory
# All passwords are generated and stored in ${VERSION}/notes
# All traffic is SSL encrypted and the certificate authority is stored in ${VERSION/ca.crt
# ${VERSION}/temp is mounted as /temp on all containers so its easy to move files around
# ${VERSION}/kibana.yml can be edited and kibana container restarted for features

# must have docker and docker-compose installed and be part of docker group

# cleanup.sh is created in ${VERSION} which will clean up and remove deployment

# Once the deployment is complete you can goto https://IPofHost:5601


# set basedir
BASEDIR=$(pwd)

# colors
red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

# get version and set major minor bugfix or print help
if [ -z ${1} ]; then
  echo "${green}Usage:${reset} ./`basename $0` {VERSION}  ${green}EXAMPLE${reset} ./deploy-elastic.sh 7.9.0  ${red}Only works for 6.x and 7.x${reset}"
  exit
else
  VERSION=${1}
  re="^[6-8]{1}[.][0-9]{1,2}[.][0-9]{1,2}$"
  if [[ ${1} =~ ${re} ]]; then
    MAJOR="$(echo ${1} | awk -F. '{ print $1 }')"
    MINOR="$(echo ${1} | awk -F. '{ print $2 }')"
    BUGFIX="$(echo ${1} | awk -F. '{ print $3 }')"
  else
    echo "${green}Usage:${reset} ./`basename $0` {VERSION}  ${red}Please use Full valid versions such as 7.9.0${reset}"
    exit
  fi
fi

# check vm.max_map_count
COUNT=`sysctl vm.max_map_count | awk {' print $3 '}`
if [ ${COUNT} -le "262144" ]; then
  echo "${green}[DEBUG]${reset} vm.max_map_count is ${COUNT}"
else
  echo "${red}[DEBUG]${reset} vm.max_map_count needs to be set to 262144.  Please run sudo sysctl -w vm.max_map_count=262144"
fi

# check to ensure docker is running and you can run docker commands
docker info >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "${red}[DEBUG]${reset} Docker is not running or you are not part of the docker group"
  exit
fi

# check to ensure docker-compose is installed
docker-compose version >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "${red}[DEBUG]${reset} docker-compose is not installed.  Please install and try again"
  exit
fi

# check to see if containers/networks/volumes exists
for name in es01 es02 es03 kibana
do
  if [ $(docker ps -a --format '{{.Names}}' | grep -c ${name}) -ge 1  ]; then
    echo "${red}[DEBUG]${reset} Container ${green}${name}${reset} exists.  Please remove and try again"
    exit
  fi
done
for name in es_default
do
  if [ $(docker network ls --format '{{.Name}}' | grep -c ${name}) -ge 1 ]; then
    echo "${red}[DEBUG]${reset} Network ${green}${name}${reset} exists.  Please remove and try again"
    exit
  fi
done
for name in es_data01 es_data02 es_data03 es_certs
do
  if [ $(docker volume ls --format '{{.Name}}' | grep -c ${name}) -ge 1 ]; then
    echo "${red}[DEBUG]${reset} Volume ${green}${name}${reset} exists.  Please remove and try again"
    exit
  fi
done

# docker pull image and if unable to pull exit
echo "${green}[DEBUG]${reset} Pulling ${VERSION} images... might take a while"
docker pull docker.elastic.co/elasticsearch/elasticsearch:${VERSION} >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "${red}[DEBUG]${reset} Unable to pull ${VERSION} of elasticsearch. valid version? exiting"
  exit
fi

docker pull docker.elastic.co/kibana/kibana:${VERSION} >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "${red}[DEBUG]${reset} Unable to pull ${VERSION} of kibana.  valid version? exiting"
  exit
fi

########################################################################################################
# all the checks are done now to start building!

# create directory structure and needed files
WORKDIR="${BASEDIR}/${VERSION}"
mkdir -p ${WORKDIR}
cd ${WORKDIR}
mkdir temp
echo "${green}[DEBUG]${reset} Created ${VERSION} directory and some files"

# create cleanup script
echo "${green}[DEBUG]${reset} Creating cleanup script to cleanup this deployment"

cat > cleanup.sh<<EOF
#!/bin/sh

echo "${green}[DEBUG]${reset} Removing es01,es02,es03,kibana,es_default network,es_data01,es_data02,es_data03,es_certs volumes"

docker-compose down >/dev/null 2>&1
docker rm es01 >/dev/null 2>&1
docker rm es02 >/dev/null 2>&1
docker rm es03 >/dev/null 2>&1
docker rm kibana >/dev/null 2>&1
docker network rm es_default >/dev/null 2>&1
docker volume rm es_data01 >/dev/null 2>&1
docker volume rm es_data02 >/dev/null 2>&1
docker volume rm es_data03 >/dev/null 2>&1
docker volume rm es_certs >/dev/null 2>&1

cd ${BASEDIR}
rm -rf ${WORKDIR}
EOF
chmod a+x cleanup.sh

# generate temp elastic password
ELASTIC_PASSWORD=`openssl rand -base64 29 | tr -d "=+/" | cut -c1-25`
echo "${green}[DEBUG]${reset} Setting temp password for elastic as ${ELASTIC_PASSWORD}"

# create temp kibana.yml
cat > kibana.yml<<EOF
elasticsearch.user: "elstic"
elasticsearch.password: "${ELASTIC_PASSWORD}"
EOF

# create env file
echo "${green}[DEBUG]${reset} Creating .env file"
cat > .env<<EOF
COMPOSE_PROJECT_NAME=es
CERTS_DIR=/usr/share/elasticsearch/config/certificates
KIBANA_CERTS_DIR=/usr/share/kibana/config/certificates
ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
COMPOSE_HTTP_TIMEOUT=600
EOF

# create instances file
echo "${green}[DEBUG]${reset} Creating instances.yml"
cat > instances.yml<<EOF
instances:
  - name: es01
    dns:
      - es01
      - localhost
    ip:
      - 127.0.0.1

  - name: es02
    dns:
      - es02
      - localhost
    ip:
      - 127.0.0.1

  - name: es03
    dns:
      - es03
      - localhost
    ip:
      - 127.0.0.1

  - name: kibana
    dns:
      - kibana
      - localhost
    ip:
      - 127.0.0.1
EOF

# create create-certs.yml & docker-compose.yml
if [ ${MAJOR} = "7" ]; then
  # create create-certs.yml
  echo "${green}[DEBUG]${reset} Creating create-certs.yml"
  if [ ${MINOR} -ge "6" ]; then
    cat > create-certs.yml<<EOF
version: '2.2'

services:
  create_certs:
    container_name: create_certs
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    command: >
      bash -c '
        if [[ ! -f /certs/bundle.zip ]]; then
          bin/elasticsearch-certutil cert --silent --pem --in config/certificates/instances.yml -out /certs/bundle.zip;
          unzip /certs/bundle.zip -d /certs;
        fi;
        chown -R 1000:0 /certs
      '
    user: "0"
    working_dir: /usr/share/elasticsearch
    volumes: ['certs:/certs', '.:/usr/share/elasticsearch/config/certificates']

volumes: {"certs"}
EOF
    else
      cat > create-certs.yml<<EOF
version: '2.2'

services:
  create_certs:
    container_name: create_certs
    image: docker.elastic.co/elasticsearch/elasticsearch:7.5.2
    command: >
      bash -c '
        yum install -y -q -e 0 unzip;
        if [[ ! -f /certs/bundle.zip ]]; then
          bin/elasticsearch-certutil cert --silent --pem --in config/certificates/instances.yml -out /certs/bundle.zip;
          unzip /certs/bundle.zip -d /certs; 
        fi;
        chown -R 1000:0 /certs
      '
    user: "0"
    working_dir: /usr/share/elasticsearch
    volumes: ['certs:/certs', '.:/usr/share/elasticsearch/config/certificates']

volumes: {"certs"}
EOF
    fi

  # create docker-compose.yml
  echo "${green}[DEBUG]${reset} Creating docker-compose.yml"
  cat > docker-compose.yml<<EOF
version: '2.2'

services:
  es01:
    container_name: es01
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es01
      - cluster.name=docker-cluster
      - discovery.seed_hosts=es01,es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - bootstrap.memory_lock=true
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - xpack.license.self_generated.type=trial
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.http.ssl.key=\$CERTS_DIR/es01/es01.key
      - xpack.security.http.ssl.certificate_authorities=\$CERTS_DIR/ca/ca.crt
      - xpack.security.http.ssl.certificate=\$CERTS_DIR/es01/es01.crt
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.verification_mode=certificate
      - xpack.security.transport.ssl.certificate_authorities=\$CERTS_DIR/ca/ca.crt
      - xpack.security.transport.ssl.certificate=\$CERTS_DIR/es01/es01.crt
      - xpack.security.transport.ssl.key=\$CERTS_DIR/es01/es01.key
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes: ['data01:/usr/share/elasticsearch/data', 'certs:\$CERTS_DIR', './temp:/temp']
    ports:
      - 9200:9200
    healthcheck:
      test: curl --cacert \$CERTS_DIR/ca/ca.crt -s https://localhost:9200 >/dev/null; if [[ $$? == 52 ]]; then echo 0; else echo 1; fi
      interval: 30s
      timeout: 10s
      retries: 5

  es02:
    container_name: es02
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es02
      - cluster.name=docker-cluster
      - discovery.seed_hosts=es01,es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - bootstrap.memory_lock=true
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - xpack.license.self_generated.type=trial
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.http.ssl.key=\$CERTS_DIR/es02/es02.key
      - xpack.security.http.ssl.certificate_authorities=\$CERTS_DIR/ca/ca.crt
      - xpack.security.http.ssl.certificate=\$CERTS_DIR/es02/es02.crt
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.verification_mode=certificate
      - xpack.security.transport.ssl.certificate_authorities=\$CERTS_DIR/ca/ca.crt
      - xpack.security.transport.ssl.certificate=\$CERTS_DIR/es02/es02.crt
      - xpack.security.transport.ssl.key=\$CERTS_DIR/es02/es02.key
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes: ['data02:/usr/share/elasticsearch/data', 'certs:\$CERTS_DIR', './temp:/temp']

  es03:
    container_name: es03
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es03
      - cluster.name=docker-cluster
      - discovery.seed_hosts=es01,es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - bootstrap.memory_lock=true
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - xpack.license.self_generated.type=trial
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.http.ssl.key=\$CERTS_DIR/es02/es02.key
      - xpack.security.http.ssl.certificate_authorities=\$CERTS_DIR/ca/ca.crt
      - xpack.security.http.ssl.certificate=\$CERTS_DIR/es02/es02.crt
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.verification_mode=certificate
      - xpack.security.transport.ssl.certificate_authorities=\$CERTS_DIR/ca/ca.crt
      - xpack.security.transport.ssl.certificate=\$CERTS_DIR/es02/es02.crt
      - xpack.security.transport.ssl.key=\$CERTS_DIR/es02/es02.key
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes: ['data03:/usr/share/elasticsearch/data', 'certs:\$CERTS_DIR', './temp:/temp']

  wait_until_ready:
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    command: /usr/bin/true
    depends_on: {"es01": {"condition": "service_healthy"}}

  kibana:
    container_name: kibana
    image:  docker.elastic.co/kibana/kibana:${VERSION}
    environment:
      - SERVER_NAME=kibana
      - SERVER_HOST="0"
      - ELASTICSEARCH_HOSTS=https://es01:9200
      - ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES=\$KIBANA_CERTS_DIR/ca/ca.crt
      - SERVER_SSL_CERTIFICATE=\$KIBANA_CERTS_DIR/kibana/kibana.crt
      - SERVER_SSL_KEY=\$KIBANA_CERTS_DIR/kibana/kibana.key
      - SERVER_SSL_ENABLED=true
    volumes: ['./kibana.yml:/usr/share/kibana/config/kibana.yml', 'certs:\$KIBANA_CERTS_DIR', './temp:/temp']
    ports:
      - 5601:5601

volumes: {"data01", "data02", "data03", "certs"}
EOF

elif [ ${MAJOR} = "6" ]; then
  # create create-certs.yml
  echo "${green}[DEBUG]${reset} Creating create-certs.yml"
  cat > create-certs.yml<<EOF
version: '2.2'

services:
  create_certs:
    container_name: create_certs
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    command: >
      bash -c '
        if [[ ! -d config/certificates/certs ]]; then
          mkdir config/certificates/certs;
        fi;
        if [[ ! -f /local/certs/bundle.zip ]]; then
          bin/elasticsearch-certgen --silent --in config/certificates/instances.yml --out config/certificates/certs/bundle.zip;
          unzip config/certificates/certs/bundle.zip -d config/certificates/certs;
        fi;
        chgrp -R 0 config/certificates/certs
      '
    user: \${UID:-1000}
    working_dir: /usr/share/elasticsearch
    volumes: ['.:/usr/share/elasticsearch/config/certificates']
EOF

  # create docker-compose.yml
  echo "${green}[DEBUG]${reset} Creating docker-compose.yml"
  cat > docker-compose.yml<<EOF
version: '2.2'

services:
  es01:
    container_name: es01
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es01
      - cluster.name=docker-cluster
      - discovery.zen.minimum_master_nodes=2
      - discovery.zen.ping.unicast.hosts=es01,es02,es03
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - xpack.license.self_generated.type=trial
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.verification_mode=certificate
      - xpack.ssl.certificate_authorities=\$CERTS_DIR/ca/ca.crt
      - xpack.ssl.certificate=\$CERTS_DIR/es01/es01.crt
      - xpack.ssl.key=\$CERTS_DIR/es01/es01.key
    volumes: ['data01:/usr/share/elasticsearch/data', './certs:\$CERTS_DIR', './temp:/temp']
    ports:
      - 9200:9200
    healthcheck:
      test: curl --cacert \$CERTS_DIR/ca/ca.crt -s https://localhost:9200 >/dev/null; if [[ $$? == 52 ]]; then echo 0; else echo 1; fi
      interval: 30s
      timeout: 10s
      retries: 25

  es02:
    container_name: es02
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es02
      - cluster.name=docker-cluster
      - discovery.zen.minimum_master_nodes=2
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - discovery.zen.ping.unicast.hosts=es01,es02,es03
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - xpack.license.self_generated.type=trial
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.verification_mode=certificate
      - xpack.ssl.certificate_authorities=\$CERTS_DIR/ca/ca.crt
      - xpack.ssl.certificate=\$CERTS_DIR/es02/es02.crt
      - xpack.ssl.key=\$CERTS_DIR/es02/es02.key
    volumes: ['data02:/usr/share/elasticsearch/data', './certs:\$CERTS_DIR', './temp:/temp']

  es03:
    container_name: es03
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es03
      - cluster.name=docker-cluster
      - discovery.zen.minimum_master_nodes=2
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - discovery.zen.ping.unicast.hosts=es01,es02,es03
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - xpack.license.self_generated.type=trial
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.verification_mode=certificate
      - xpack.ssl.certificate_authorities=\$CERTS_DIR/ca/ca.crt
      - xpack.ssl.certificate=\$CERTS_DIR/es02/es02.crt
      - xpack.ssl.key=\$CERTS_DIR/es02/es02.key
    volumes: ['data03:/usr/share/elasticsearch/data', './certs:\$CERTS_DIR', './temp:/temp']

  wait_until_ready:
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    command: /usr/bin/true
    depends_on: {"es01": {"condition": "service_healthy"}}

  kibana:
    container_name: kibana
    image: docker.elastic.co/kibana/kibana:${VERSION}
    environment:
      - SERVER_NAME=kibana
      - SERVER_HOST="0"
      - ELASTICSEARCH_HOSTS=https://es01:9200
      - ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES=\$KIBANA_CERTS_DIR/ca/ca.crt
      - SERVER_SSL_CERTIFICATE=\$KIBANA_CERTS_DIR/kibana/kibana.crt
      - SERVER_SSL_KEY=\$KIBANA_CERTS_DIR/kibana/kibana.key
      - SERVER_SSL_ENABLED=true
    volumes: ['./kibana.yml:/usr/share/kibana/config/kibana.yml', './certs:\$KIBANA_CERTS_DIR', './temp:/temp']
    ports:
      - 5601:5601


volumes: {"data01": {"driver": "local"}, "data02": {"driver": "local"}, "data03": {"driver": "local"}}
EOF

fi

# create certificates
echo "${green}[DEBUG]${reset} Create certificates"
docker-compose -f create-certs.yml run --rm create_certs

# start cluster
echo "${green}[DEBUG]${reset} Starting our deployment"
docker-compose up -d

# wait for cluster to be healthy
if [ ${MAJOR} = "7" ]; then
  while true
  do
    if [ `docker run --rm -v es_certs:/certs --network=es_default docker.elastic.co/elasticsearch/elasticsearch:${VERSION} curl -s --cacert /certs/ca/ca.crt -u elastic:${ELASTIC_PASSWORD} https://es01:9200/_cluster/health | grep -c green` = 1 ]; then
      break
    else
      echo "${green}[DEBUG]${reset} Waiting for cluster to turn green to set passwords..."
    fi
    sleep 10
  done
elif [ ${MAJOR} = "6" ]; then
  while true
  do
    if [ `curl --cacert certs/ca/ca.crt -s -u elastic:${ELASTIC_PASSWORD} https://localhost:9200/_cluster/health | grep -c green` = 1 ]; then
      break
    else
      echo "${green}[DEBUG]${reset} Waiting for cluster to turn green to set passwords..."
    fi
    sleep 10
  done
fi

# setup passwords
echo "${green}[DEBUG]${reset} Setting passwords and storing it in ${PWD}/notes"
if [ ${MAJOR} = "7" ]; then
  if [ ${MINOR} -ge "6" ]; then
    docker exec es01 /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch --url https://localhost:9200" | tee -a notes
  else
    docker exec es01 /bin/bash -c "bin/elasticsearch-setup-passwords \
auto --batch \
-Expack.security.http.ssl.certificate=certificates/es01/es01.crt \
-Expack.security.http.ssl.certificate_authorities=certificates/ca/ca.crt \
-Expack.security.http.ssl.key=certificates/es01/es01.key \
--url https://localhost:9200" | tee -a notes
  fi
elif [ ${MAJOR} = "6" ]; then
#  docker exec es01 /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch -Expack.ssl.certificate=certificates/es01/es01.crt -Expack.ssl.certificate_authorities=certificates/ca/ca.crt -Expack.ssl.key=certificates/es01/es01.key --url https://localhost:9200" | tee -a notes
  docker exec es01 /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch -Expack.security.http.ssl.certificate_authorities=certificates/ca/ca.crt --url https://localhost:9200" | tee -a notes
fi

# grab the new elastic password
PASSWD=`cat notes | grep "PASSWORD elastic" | awk {' print $4 '}`

# create kibana.yml
cat > kibana.yml<<EOF
elasticsearch.username: "elastic"
elasticsearch.password: "${PASSWD}"
EOF

# restart kibana
echo "${green}[DEBUG]${reset} Restarting kibana to pick up the new elastic password"
docker restart kibana

# copy the certificate authority into the homedir for the project
echo "${green}[DEBUG]${reset} Copying the certificate authority into the project folder"
if [ ${MAJOR} = "7" ]; then
  docker exec es01 /bin/bash -c "cp /usr/share/elasticsearch/config/certificates/ca/ca.* /temp/"
  mv ${WORKDIR}/temp/ca.* ${WORKDIR}/
elif [ ${MAJOR} = "6" ]; then
  cp ${WORKDIR}/certs/ca/ca.* ${WORKDIR}/
fi

echo "${green}[DEBUG]${reset} Complete.  "
echo ""

