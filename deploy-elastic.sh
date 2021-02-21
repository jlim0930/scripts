#!/usr/bin/env bash


# justin lim <justin@isthecoolest.ninja>
# version 3.0 - added minio & full option
# version 2.0 - added monitoring option
# version 1.0 - 3 node deployment with kibana

# $ curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/deploy-elastic.sh -o deploy-elastic.sh
# $ sh ./deploy-elastic.sh stack {VERSION}
# $ sh ./deploy-elastac.sh monitor {VERSION}
# $ sh ./deploy-elastic.sh minio {VERSION}
# $ sh ./deploy-elastic.sh full {VERSION}
#
# es01 is exposed on 9200
# kibana is exposed on 5601

#################################################################################################################################

# set basedir
BASEDIR=$(pwd)

# colors
red=`tput setaf 1`
green=`tput setaf 2`
blue=`tput setaf 4`
reset=`tput sgr0`

help() {
  echo -e  "${green}Usage:${reset} ./`basename $0` command version"
  echo -e "\t${blue}COMMAND${reset}"
  echo -e "\t${blue}stack${reset} - Starts deployment.  Must give the option of full version to deploy"
  echo -e "\t\tExample: ./`basename $0` stack 7.10.2"
  echo -e "\t${blue}monitor${reset} - Adds metricbeat collections monitoring.  Must have a deployment running first. Specify the verion of the running instance. Only for version 6.5+"
  echo -e "\t\tExample: ./`basename $0` monitor 7.10.2"
  echo -e "\t${blue}minio${reset} - Adds minio container and configures minio01 snapshot repository onto the deployment.  Must have a deployment running first."
  echo -e "\t\tExample: ./`basename $0` minio 7.10.2"
  echo -e "\t${blue}full${reset} - Runs the full stack with monitoring and minio."
  echo -e "\t\tExample: ./`basename $0` full 7.10.2"
  exit
}

version() {
#  local arg=$1
  if [ -z ${1} ]; then
    help
  else
    re="^[6-8]{1}[.][0-9]{1,2}[.][0-9]{1,2}$"
    if [[ ${1} =~ ${re} ]]; then
      MAJOR="$(echo ${1} | awk -F. '{ print $1 }')"
      MINOR="$(echo ${1} | awk -F. '{ print $2 }')"
      BUGFIX="$(echo ${1} | awk -F. '{ print $3 }')"
    else
      help
    fi
  fi
}

checkdocker() {
  # check vm.max_map_count
  if [ "`uname -s`" != "Darwin" ]; then
    COUNT=`sysctl vm.max_map_count | awk {' print $3 '}`
    if [ ${COUNT} -le "262144" ]; then
      echo "${green}[DEBUG]${reset} Ensuring vm.max_map_count is ${COUNT}... proceeding"
    else
      echo "${red}[DEBUG]${reset} vm.max_map_count needs to be set to 262144.  Please run sudo sysctl -w vm.max_map_count=262144"
      exit;
    fi
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
}

checkcontainer() {
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
}

checkhealth() {
  # check to make sure that the deployment is in GREEN status
  if [ ${MAJOR} = "7" ]; then
    while true
    do
      if [ `docker run --rm -v es_certs:/certs --network=es_default docker.elastic.co/elasticsearch/elasticsearch:${VERSION} curl -s --cacert /certs/ca/ca.crt -u elastic:${PASSWD}   https://es01:9200/_cluster/health | grep -c green` = 1 ]; then
        break
      else
        echo "${red}[DEBUG]${reset} elasticsearch is unhealthy. Checking again in 2 seconds.. if this doesnt finish in ~ 30 seconds ctrl-c"
        sleep 2
      fi
    done
  elif [ ${MAJOR} = "6" ]; then
    while true
    do
      if [ `curl --cacert certs/ca/ca.crt -s -u elastic:${PASSWD} https://localhost:9200/_cluster/health | grep -c green` = 1 ]; then
        break
      else
        echo "${red}[DEBUG]${reset} elasticsearch is unhealthy. Checking again in 2 seconds... if this doesnt finish in ~ 30 seconds ctrl-c"
        sleep 2
      fi
    done
  fi
  echo "${green}[DEBUG]${reset} elasticsearch health is ${green}GREEN${reset} moving forward."
}

cleanup() {
  # generate cleanup script
  cat > cleanup.sh<<EOF
#!/bin/sh

echo "${green}[DEBUG]${reset} Cleaning UP!"

STRING="-f stack-compose.yml"
LIST="es01 es02 es03 kibana"

if [ -f monitoring-compose.yml ]; then
  STRING="\${STRING} -f monitoring-compose.yml"
  LIST="\${LIST} metricbeat filebeat"
fi

if [ -f minio-compose.yml ]; then
  STRING="\${STRING} -f minio-compose.yml"
  LIST="\${LIST} minio01 es_mc_1"
fi

docker-compose \${STRING} down >/dev/null 2>&1

for item in \${LIST}
do
  docker rm \${item} > /dev/null 2>&1
done

docker network rm es_default >/dev/null 2>&1
docker volume rm es_data01 >/dev/null 2>&1
docker volume rm es_data02 >/dev/null 2>&1
docker volume rm es_data03 >/dev/null 2>&1
docker volume rm es_certs >/dev/null 2>&1

cd ${BASEDIR}
rm -rf ${WORKDIR}
EOF
   chmod a+x cleanup.sh
}

grabpasswd() {
  # grab the elastic password
  PASSWD=`cat notes | grep "PASSWORD elastic" | awk {' print $4 '}`
  echo "${green}[DEBUG]${reset} elastic user's password found ${PASSWD}"
}

pullmain() {
  # checking for image - elasticsearch
  docker image inspect docker.elastic.co/elasticsearch/elasticsearch:${VERSION} > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${green}[DEBUG]${reset} Pulling elasticsearch image ${VERSION} ... might take a while"
    docker pull docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    if [ $? -ne 0 ]; then
      echo "${red}[DEBUG]${reset} Unable to pull elasticsearch ${VERSION}. valid version? exiting."
      exit
    fi
  else
    echo "${green}[DEBUG]${reset} elasticsearch docker image already exists.. moving forward.."
  fi

  # checking for image - kibana
  docker image inspect docker.elastic.co/kibana/kibana:${VERSION} > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${green}[DEBUG]${reset} Pulling kibana image ${VERSION} ... might take a while"
    docker pull docker.elastic.co/kibana/kibana:${VERSION}
    if [ $? -ne 0 ]; then
      echo "${red}[DEBUG]${reset} Unable to pull kibana${VERSION}.  valid version? exiting"
      exit
    fi
  else
    echo "${green}[DEBUG]${reset} kibana docker image already exists.. moving forward.."
  fi
}

pullbeats() {
  # checking for image - metricbeat
  docker image inspect docker.elastic.co/beats/metricbeat:${VERSION} > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${green}[DEBUG]${reset} Pulling metricbeat ${VERSION} images... might take a while"
    docker pull docker.elastic.co/beats/metricbeat:${VERSION}
    if [ $? -ne 0 ]; then
      echo "${red}[DEBUG]${reset} Unable to pull metricbeat ${VERSION}.  valid version? exiting"
      exit
    fi
  else
    echo "${green}[DEBUG]${reset} metricbeat docker image already exists.. moving forward.."
  fi

  # checking for image - filebeat
  docker image inspect docker.elastic.co/beats/filebeat:${VERSION} > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${green}[DEBUG]${reset} Pulling filebeat ${VERSION} images... might take a while"
    docker pull docker.elastic.co/beats/filebeat:${VERSION}
    if [ $? -ne 0 ]; then
      echo "${red}[DEBUG]${reset} Unable to pull filebeat ${VERSION}.  valid version? exiting"
      exit
    fi
  else
    echo "${green}[DEBUG]${reset} filebeat docker image already exists.. moving forward.."
  fi
}

pullminio() {
  # checking for image - minio
  docker image inspect minio/minio:latest > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${green}[DEBUG]${reset} Pulling minio images... might take a while"
    docker pull minio/minio
    if [ $? -ne 0  ]; then
      echo "${red}[DEBUG]${reset} Unable to pull minio. "
      exit
    fi
  else
    echo "${green}[DEBUG]${reset} minio docker image already exists.. moving forward.."
  fi
}


stack() {
  VERSION=${1}
  version ${VERSION}

  echo "${green}==== Deploying elasticsearch & kibana ====${reset}"
  checkdocker
  checkcontainer
  pullmain

  # create directory structure and needed files
  WORKDIR="${BASEDIR}/${VERSION}"
  mkdir -p ${WORKDIR}
  cd ${WORKDIR}
  mkdir temp
  cat > elasticsearch.yml<<EOF
cluster.name: "docker-cluster"
network.host: 0.0.0.0
EOF
  chown 1000 elasticsearch.* >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} Created ${VERSION} directory and some files"

  #
  # create cleanup script
  cleanup

  # generate temp elastic password
  PASSWD=`openssl rand -base64 29 | tr -d "=+/" | cut -c1-25`
  echo "${green}[DEBUG]${reset} Setting temp password for elastic as ${PASSWD}"

  # create temp kibana.yml
  cat > kibana.yml<<EOF
elasticsearch.user: "elstic"
elasticsearch.password: "${PASSWD}"
EOF

  # create env file
  echo "${green}[DEBUG]${reset} Creating .env file"
  cat > .env<<EOF
COMPOSE_PROJECT_NAME=es
CERTS_DIR=/usr/share/elasticsearch/config/certificates
KIBANA_CERTS_DIR=/usr/share/kibana/config/certificates
ELASTIC_PASSWORD=${PASSWD}
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

  # create create-certs.yml & stack-compose.yml
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
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
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

    # create stack-compose.yml
    echo "${green}[DEBUG]${reset} Creating stack-compose.yml"
    cat > stack-compose.yml<<EOF
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
      - ELASTIC_PASSWORD=${PASSWD}
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
    labels:
      co.elastic.logs/module: elasticsearch
    volumes: ['data01:/usr/share/elasticsearch/data', 'certs:\$CERTS_DIR', './temp:/temp', './elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml']
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
      - ELASTIC_PASSWORD=${PASSWD}
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
    labels:
      co.elastic.logs/module: elasticsearch
    volumes: ['data02:/usr/share/elasticsearch/data', 'certs:\$CERTS_DIR', './temp:/temp', './elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml']

  es03:
    container_name: es03
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es03
      - cluster.name=docker-cluster
      - discovery.seed_hosts=es01,es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - ELASTIC_PASSWORD=${PASSWD}
      - bootstrap.memory_lock=true
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - xpack.license.self_generated.type=trial
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.http.ssl.key=\$CERTS_DIR/es03/es03.key
      - xpack.security.http.ssl.certificate_authorities=\$CERTS_DIR/ca/ca.crt
      - xpack.security.http.ssl.certificate=\$CERTS_DIR/es03/es03.crt
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.verification_mode=certificate
      - xpack.security.transport.ssl.certificate_authorities=\$CERTS_DIR/ca/ca.crt
      - xpack.security.transport.ssl.certificate=\$CERTS_DIR/es03/es03.crt
      - xpack.security.transport.ssl.key=\$CERTS_DIR/es03/es03.key
    ulimits:
      memlock:
        soft: -1
        hard: -1
    labels:
      co.elastic.logs/module: elasticsearch
    volumes: ['data03:/usr/share/elasticsearch/data', 'certs:\$CERTS_DIR', './temp:/temp', './elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml']


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
      - ELASTICSEARCH_HOSTS=["https://es01:9200","https://es02:9200","https://es03:9200"]
      - ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES=\$KIBANA_CERTS_DIR/ca/ca.crt
      - ELASTICSEARCH_SSL_VERIFICATIONMODE=certificate
      - SERVER_SSL_CERTIFICATE=\$KIBANA_CERTS_DIR/kibana/kibana.crt
      - SERVER_SSL_KEY=\$KIBANA_CERTS_DIR/kibana/kibana.key
      - SERVER_SSL_ENABLED=true
    labels:
      co.elastic.logs/module: kibana
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

    # create stack-compose.yml
    echo "${green}[DEBUG]${reset} Creating stack-compose.yml"
    cat > stack-compose.yml<<EOF
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
      - ELASTIC_PASSWORD=${PASSWD}
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - xpack.license.self_generated.type=trial
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.verification_mode=certificate
      - xpack.ssl.certificate_authorities=\$CERTS_DIR/ca/ca.crt
      - xpack.ssl.certificate=\$CERTS_DIR/es01/es01.crt
      - xpack.ssl.key=\$CERTS_DIR/es01/es01.key
    labels:
      co.elastic.logs/module: elasticsearch
    volumes: ['data01:/usr/share/elasticsearch/data', './certs:\$CERTS_DIR', './temp:/temp', './elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml']
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
      - ELASTIC_PASSWORD=${PASSWD}
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
    labels:
      co.elastic.logs/module: elasticsearch
    volumes: ['data02:/usr/share/elasticsearch/data', './certs:\$CERTS_DIR', './temp:/temp', './elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml']

  es03:
    container_name: es03
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es03
      - cluster.name=docker-cluster
      - discovery.zen.minimum_master_nodes=2
      - ELASTIC_PASSWORD=${PASSWD}
      - discovery.zen.ping.unicast.hosts=es01,es02,es03
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - xpack.license.self_generated.type=trial
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.verification_mode=certificate
      - xpack.ssl.certificate_authorities=\$CERTS_DIR/ca/ca.crt
      - xpack.ssl.certificate=\$CERTS_DIR/es03/es03.crt
      - xpack.ssl.key=\$CERTS_DIR/es03/es03.key
    labels:
      co.elastic.logs/module: elasticsearch
    volumes: ['data03:/usr/share/elasticsearch/data', './certs:\$CERTS_DIR', './temp:/temp', './elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml']

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
      - ELASTICSEARCH_HOSTS=["https://es01:9200","https://es02:9200","https://es03:9200"]
      - ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES=\$KIBANA_CERTS_DIR/ca/ca.crt
      - ELASTICSEARCH_SSL_VERIFICATIONMODE=certificate
      - SERVER_SSL_CERTIFICATE=\$KIBANA_CERTS_DIR/kibana/kibana.crt
      - SERVER_SSL_KEY=\$KIBANA_CERTS_DIR/kibana/kibana.key
      - SERVER_SSL_ENABLED=true
    labels:
      co.elastic.logs/module: kibana
    volumes: ['./kibana.yml:/usr/share/kibana/config/kibana.yml', './certs:\$KIBANA_CERTS_DIR', './temp:/temp']
    ports:
      - 5601:5601


volumes: {"data01": {"driver": "local"}, "data02": {"driver": "local"}, "data03": {"driver": "local"}}
EOF

    # fix for 6.5 and below for ELASTICSEARCH_HOST
    if [ ${MINOR} -le "5" ]; then
      if [ "`uname -s`" != "Darwin" ]; then
        sed -i 's/ELASTICSEARCH_HOSTS.*/ELASTICSEARCH_URL=https://es01:9200/g' stack-compose.yml
      else
        sed -i '' -E 's/ELASTICSEARCH_HOST.*/ELASTICSEARCH_URL=https:\/\/es01:9200/g' stack-compose.yml
      fi
    fi
  fi

  # create certificates
  echo "${green}[DEBUG]${reset} Create certificates"
  docker-compose -f create-certs.yml run --rm create_certs

  # start cluster
  echo "${green}[DEBUG]${reset} Starting our deployment"
  docker-compose -f stack-compose.yml up -d

  # wait for cluster to be healthy
  checkhealth

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
  grabpasswd

  # generate kibana encryption key
  ENCRYPTION_KEY=`openssl rand -base64 40 | tr -d "=+/" | cut -c1-32`

  # create kibana.yml

  if [ ${MAJOR} = "6" ]; then
    cat > kibana.yml<<EOF
elasticsearch.username: "elastic"
elasticsearch.password: "${PASSWD}"
xpack.security.encryptionKey: "${ENCRYPTION_KEY}"
xpack.reporting.encryptionKey: "${ENCRYPTION_KEY}"
EOF
  elif [ ${MAJOR} = "7" ]; then
    if [ ${MINOR} -lt "7" ]; then
      cat > kibana.yml<<EOF
elasticsearch.username: "elastic"
elasticsearch.password: "${PASSWD}"
xpack.security.encryptionKey: "${ENCRYPTION_KEY}"
xpack.reporting.encryptionKey: "${ENCRYPTION_KEY}"
EOF
    elif [ ${MINOR} -ge "7" ]; then
      cat > kibana.yml<<EOF
elasticsearch.username: "elastic"
elasticsearch.password: "${PASSWD}"
xpack.security.encryptionKey: "${ENCRYPTION_KEY}"
xpack.reporting.encryptionKey: "${ENCRYPTION_KEY}"
xpack.encryptedSavedObjects.encryptionKey: "${ENCRYPTION_KEY}"
EOF
    fi
  fi

  # restart kibana
  echo "${green}[DEBUG]${reset} Restarting kibana to pick up the new elastic password"
  docker restart kibana
  sleep 10

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

}

 monitor() {
  VERSION=${1}
  version ${VERSION}

  # check to make sure that ES is 6.5 or greater
  if [ ${MAJOR} = "6" ]; then
    if [ ${MINOR} -le "4" ]; then
      echo "${red}[DEBUG]${reset} metricbeats collections started with 6.5+.  Please use legacy collections method"
      return 1
    else
      echo "${green}==== Deploying metricbeat collections monitoring ====${reset}"
    fi
  else
    echo "${green}==== Deploying metricbeat collections monitoring ====${reset}"
  fi

  # check for workdir and exit if there are no deployments
  WORKDIR="${BASEDIR}/${VERSION}"
  if [ -z ${WORKDIR} ]; then
    echo "${red}[DEBUG]${reset} Please deploy first before setting up monitoring"
    exit
  fi

  # start building
  cd ${WORKDIR}

  # grab the elastic password
  grabpasswd

  # check to make sure that the deployment is in GREEN status
  checkdocker
  checkhealth
  # pull beats images
  pullbeats

  # add MB_CERTS_DIR & FB_CERTS to .env
  cat >> .env<<EOF
MB_CERTS_DIR=/usr/share/metricbeat/certificates
FB_CERTS_DIR=/usr/share/filebeat/certificates
EOF
  echo "${green}[DEBUG]${reset} Updated .env to include MB_CERTS_DIR & FB_CERTS_DIR"

  # add xpack.monitoring.kibana.collection.enabled: false to kibana.yml and restart kibana for 6.x
  echo "xpack.monitoring.kibana.collection.enabled: false" >> kibana.yml
  docker restart kibana >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${red}[DEBUG]${reset} Unable to restart kibana"
    exit
  else
    echo "${green}[DEBUG]${reset} kibana restarted after adding xpack.monitoring.kibana.collection.enabled: false"
  fi

  # create metricbeat.yml
  echo "${green}[DEBUG]${reset} Creating metricbeat.yml"
  MBYML6="#
metricbeat.modules:
# Module: elasticsearch
- module: elasticsearch
  metricsets:
    - ccr
    - cluster_stats
    - index
    - index_recovery
    - index_summary
    - ml_job
    - node_stats
    - shard
  xpack.enabled: true
  period: 10s
  hosts: [\"https://es01:9200\", \"https://es02:9200\", \"https://es03:9200\"]
  username: \"elastic\"
  password: "\"${PASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/ca.crt\"]

# Module: kibana
- module: kibana
  metricsets:
    - stats
  xpack.enabled: true
  period: 10s
  hosts: [\"https://kibana:5601\"]
  username: \"elastic\"
  password: "\"${PASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/ca.crt\"]

processors:
  - add_cloud_metadata: ~
  - add_docker_metadata: ~

output.elasticsearch:
  hosts: [\"https://es01:9200\", \"https://es02:9200\", \"https://es03:9200\"]
  username: \"elastic\"
  password: "\"${PASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/ca.crt\"]
  "

  MBYML74="#
#
http.enabled: true
http.port: 5066
http.host: 0.0.0.0
monitoring.enabled: false

metricbeat.modules:
# Module: elasticsearch
- module: elasticsearch
  metricsets:
    - ccr
    - cluster_stats
    - index
    - index_recovery
    - index_summary
    - ml_job
    - node_stats
    - shard
  xpack.enabled: true
  period: 10s
  hosts: [\"https://es01:9200\", \"https://es02:9200\", \"https://es03:9200\"]
  username: \"elastic\"
  password: "\"${PASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]

# Module: kibana
- module: kibana
  metricsets:
    - stats
  xpack.enabled: true
  period: 10s
  hosts: [\"https://kibana:5601\"]
  username: \"elastic\"
  password: "\"${PASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]

# Module: beats
- module: beat
  metricsets:
    - stats
    - state
  period: 10s
  hosts: [\"http://metricbeat:5066\", \"http://filebeat:5066\"]
  xpack.enabled: true
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]

processors:
  - add_cloud_metadata: ~
  - add_docker_metadata: ~

output.elasticsearch:
  hosts: [\"https://es01:9200\", \"https://es02:9200\", \"https://es03:9200\"]
  username: \"elastic\"
  password: "\"${PASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]
  "

  MBYML78="#
#
http.enabled: true
http.port: 5066
http.host: 0.0.0.0
monitoring.enabled: false

metricbeat.modules:
# Module: elasticsearch
- module: elasticsearch
  metricsets:
     - ccr
     - cluster_stats
     - index
     - index_recovery
     - index_summary
     - ml_job
     - node_stats
     - shard
     - enrich
  xpack.enabled: true
  period: 10s
  hosts: [\"https://es01:9200\", \"https://es02:9200\", \"https://es03:9200\"]
  username: \"elastic\"
  password: "\"${PASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]

# Module: kibana
- module: kibana
  metricsets:
    - stats
  xpack.enabled: true
  period: 10s
  hosts: [\"https://kibana:5601\"]
  username: \"elastic\"
  password: "\"${PASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]

# Module: beats
- module: beat
  metricsets:
    - stats
    - state
  period: 10s
  hosts: [\"http://metricbeat:5066\", \"http://filebeat:5066\"]
  xpack.enabled: true
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]

processors:
  - add_cloud_metadata: ~
  - add_docker_metadata: ~

output.elasticsearch:
  hosts: [\"https://es01:9200\", \"https://es02:9200\", \"https://es03:9200\"]
  username: \"elastic\"
  password: "\"${PASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]
  "

  MBYML="#
#
http.enabled: true
http.port: 5066
http.host: 0.0.0.0
monitoring.enabled: false

metricbeat.modules:
# Module: elasticsearch
- module: elasticsearch
  xpack.enabled: true
  period: 10s
  hosts: [\"https://es01:9200\", \"https://es02:9200\", \"https://es03:9200\"]
  username: \"elastic\"
  password: "\"${PASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]

# Module: kibana
- module: kibana
  metricsets:
    - stats
  xpack.enabled: true
  period: 10s
  hosts: [\"https://kibana:5601\"]
  username: \"elastic\"
  password: "\"${PASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]

# Module: beats
- module: beat
  metricsets:
    - stats
    - state
  period: 10s
  hosts: [\"http://metricbeat:5066\", \"http://filebeat:5066\"]
  xpack.enabled: true
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]

processors:
  - add_cloud_metadata: ~
  - add_docker_metadata: ~

output.elasticsearch:
  hosts: [\"https://es01:9200\", \"https://es02:9200\", \"https://es03:9200\"]
  username: \"elastic\"
  password: "\"${PASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]
  "

  if [ ${MAJOR} = "6" ]; then
    echo "${MBYML6}" > metricbeat.yml
  elif [ ${MAJOR} = "7" ]; then
    if [ ${MINOR} -le "4" ]; then
      echo "${MBYML74}" > metricbeat.yml
    elif [ ${MINOR} -le "8" ]; then
      echo "${MBYML78}" > metricbeat.yml
    else
      echo "${MBYML}" > metricbeat.yml
    fi
  fi
  chmod go-w metricbeat.yml

  # create filebeat.yml
  if [ ${MAJOR} = "7" ]; then
    cat > filebeat.yml<<EOF
#
http.enabled: true
http.port: 5066
http.host: 0.0.0.0
monitoring.enabled: false

filebeat.autodiscover:
  providers:
    - type: docker
      hints.enabled: true

filebeat.modules:
  - module: elasticsearch
  - module: kibana

processors:
  - add_cloud_metadata: ~
  - add_docker_metadata: ~

output.elasticsearch:
  hosts: ["https://es01:9200", "https://es02:9200", "https://es03:9200"]
  username: "elastic"
  password: "${PASSWD}"
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: ["/usr/share/filebeat/certificates/ca/ca.crt"]
EOF
  elif [ ${MAJOR} = "6" ]; then
    cat > filebeat.yml<<EOF
filebeat.autodiscover:
   providers:
     - type: docker
       hints.enabled: true

filebeat.modules:
  - module: elasticsearch
  - module: kibana

processors:
  - add_cloud_metadata: ~
  - add_docker_metadata: ~

output.elasticsearch:
  hosts: ["https://es01:9200", "https://es02:9200", "https://es03:9200"]
  username: "elastic"
  password: "${PASSWD}"
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: ["/usr/share/filebeat/ca.crt"]
EOF
  fi


  # create monitoring-compose.yml
  echo "${green}[DEBUG]${reset} Creating monitoring-compose.yml"
  if [ ${MAJOR} = "7" ]; then
    cat > monitoring-compose.yml<<EOF
version: '2.2'

services:
  metricbeat:
    container_name: metricbeat
    user: root
    image: docker.elastic.co/beats/metricbeat:${VERSION}
    volumes: ['./metricbeat.yml:/usr/share/metricbeat/metricbeat.yml', './temp:/temp', 'certs:\$MB_CERTS_DIR', '/var/run/docker.sock:/var/run/docker.sock:ro']
  filebeat:
    container_name: filebeat
    user: root
    image: docker.elastic.co/beats/filebeat:${VERSION}
    volumes: ['./filebeat.yml:/usr/share/filebeat/filebeat.yml', './temp:/temp', 'certs:\$FB_CERTS_DIR', '/var/lib/docker/containers:/var/lib/docker/containers:ro', '/var/run/docker.sock:/var/run/docker.sock:ro']


volumes: {"certs"}
EOF
  elif [ ${MAJOR} = "6" ]; then
    cat > monitoring-compose.yml<<EOF
version: '2.2'

services:
  metricbeat:
    container_name: metricbeat
    user: root
    image: docker.elastic.co/beats/metricbeat:${VERSION}
    volumes: ['./metricbeat.yml:/usr/share/metricbeat/metricbeat.yml', './temp:/tmp', './ca.crt:/usr/share/metricbeat/ca.crt', '/var/run/docker.sock:/var/run/docker.sock:ro']
  filebeat:
    container_name: filebeat
    user: root
    image: docker.elastic.co/beats/filebeat:${VERSION}
    volumes: ['./filebeat.yml:/usr/share/filebeat/filebeat.yml', './temp:/temp', './ca.crt:/usr/share/filebeat/ca.crt', '/var/lib/docker/containers:/var/lib/docker/containers:ro', '/var/run/docker.sock:/var/run/docker.sock:ro']

volumes: {"certs"}
EOF
  fi

  # add setting for xpack.monitoring.collection.enabled
  echo "${green}[DEBUG]${reset} Setting xpack.monitoring.collection.enabled: true"
  curl -k -u elastic:${PASSWD} -X PUT "https://localhost:9200/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "xpack.monitoring.collection.enabled": true,
    "xpack.monitoring.elasticsearch.collection.enabled": false
  }
}
' >/dev/null 2>&1

  # start service
  checkhealth
  echo "${green}[DEBUG]${reset} Sleeping for 30 seconds for things to settle before starting beats"
  sleep 30
  echo "${green}[DEBUG]${reset} Starting beats"
  docker-compose -f monitoring-compose.yml up -d >/dev/null 2>&1

}

minio() {
  VERSION=${1}
  version ${VERSION}
  echo "${green}==== Deploying minio instance and adding snapshot repository as minio01 ====${reset}"

  # check for workdir and exit if there are no deployments
  WORKDIR="${BASEDIR}/${VERSION}"
  if [ -z ${WORKDIR} ]; then
    echo "${red}[DEBUG]${reset} Please deploy first before setting up monitoring"
    exit
  fi

  # start building
  cd ${WORKDIR}

  # grab the elastic password
  grabpasswd

  # check to make sure that the deployment is in GREEN status
  checkdocker
  checkhealth

  # pull image
  pullminio

  # create minio-compose.yml
  cat > minio-compose.yml<<EOF
version: '2.2'

services:
  minio01:
    container_name: minio01
    image: minio/minio
    environment:
      - MINIO_ROOT_USER=minio
      - MINIO_ROOT_PASSWORD=minio123
    volumes: ['./data:/data', './temp:/temp']
    command: server /data
    ports:
      - 9000:9000
    healthcheck:
      test: curl http://localhost:9000/minio/health/live
      interval: 30s
      timeout: 10s
      retries: 5
  mc:
    image: minio/mc
    depends_on:
      - minio01
    entrypoint: >
      bin/sh -c '
      sleep 5;
      /usr/bin/mc config host add s3 http://minio01:9000 minio minio123 --api s3v4;
      /usr/bin/mc mb s3/elastic;
      /usr/bin/mc policy set public s3/elastic;
      '
EOF

  echo "${green}[DEBUG]${reset} Starting minio"
  docker-compose -f minio-compose.yml up -d >/dev/null 2>&1
  checkhealth


  # add to elasticsearch.yml if 7.x
  IP=`docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' minio01`
  if [ ${MAJOR} = "7" ]; then
    cat >> elasticsearch.yml<<EOF

s3.client.minio01.endpoint: "${IP}:9000"
s3.client.minio01.protocol: "http"
EOF
  fi

  # install repository-s3 plugin & add keystore items & restart container
  for instance in es01 es02 es03
  do
    docker exec ${instance} bin/elasticsearch-plugin install --batch repository-s3 >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo "${red}[DEBUG]${reset} Unable to install repository-s3 to ${instance}"
      exit
    else
      echo "${green}[DEBUG]${reset} repository-s3 installed to ${instance}"
    fi
    sleep 3
    if [ ${MAJOR} = "7" ]; then
      docker exec -i ${instance} bin/elasticsearch-keystore add -xf s3.client.minio01.access_key <<EOF
minio
EOF
      echo "${green}[DEBUG]${reset} added s3.client.minio01.access_key to keystore to ${instance}"
    docker exec -i ${instance} bin/elasticsearch-keystore add -xf s3.client.minio01.secret_key <<EOF
minio123
EOF
      echo "${green}[DEBUG]${reset} added s3.client.minio01.secret to keystore to ${instance}"
    else
      docker exec ${instance} bash -c "echo '-Des.allow_insecure_settings=true' >> config/jvm.options"
    fi
    docker restart ${instance} >/dev/null 2>&1
    echo "${green}[DEBUG]${reset} Restarting ${instance} after keystore changes"
    sleep 7
  done

  # add repsitory
  if [ ${MAJOR} = "7" ]; then
    curl -k -u elastic:${PASSWD} -XPUT "https://localhost:9200/_snapshot/minio01" -H 'Content-Type: application/json' -d'
{
  "type": "s3",
  "settings": {
    "client": "minio01",
    "bucket": "elastic",
    "path_style_access": true
  }
}' > /dev/null 2>&1
    echo "${green}[DEBUG]${reset} Added minio01 snapshot repository"
    if [ ${MINOR} -ge "4" ]; then
      curl -k -u elastic:${PASSWD} -XPUT "https://localhost:9200/_slm/policy/minio-snapshot-policy" -H 'Content-Type: application/json' -d'{  "schedule": "0 */30 * * * ?",   "name": "<minio-snapshot-{now/d}>",   "repository": "minio01",   "config": {     "partial": true  },  "retention": {     "expire_after": "5d",     "min_count": 1,     "max_count": 20   }}' > /dev/null 2>&1
      echo "${green}[DEBUG]${reset} Added minio-snapshot-policy"
    fi
  elif [ ${MAJOR} = "6" ]; then
    curl -k -u elastic:${PASSWD} -XPUT "https://localhost:9200/_snapshot/minio01" -H 'Content-Type: application/json' -d'
{
  "type": "s3",
  "settings": {
    "bucket": "elastic",
    "access_key": "minio",
    "secret_key": "minio123",
    "endpoint": "'${IP}':9000",
    "protocol": "http"
  }
}' > /dev/null 2>&1
    echo "${green}[DEBUG]${reset} Added minio01 snapshot repository"
  fi

}

# help and modes
case $1 in
  stack)
    stack ${2}
    ;;
  monitor)
    monitor ${2}
    ;;
  minio)
    minio ${2}
    ;;
  full)
    stack ${2}
    checkhealth
    monitor ${2}
    checkhealth
    minio ${2}
    ;;
  *)
    help
    ;;
esac

