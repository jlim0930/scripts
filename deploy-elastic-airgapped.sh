#!/usr/bin/env bash

# justin lim <justin@isthecoolest.ninja>
# version 4.0 - added apm-server & enterprise search(still needs some work on es but its functional)
# version 3.0 - added minio & snapshots
# version 2.0 - added monitoring option
# version 1.0 - 3 node deployment with kibana

# $ curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/deploy-elastic.sh -o deploy-elastic.sh

# es01 is exposed on 9200 with SSL
# kibana is exposed on 5601 with SSL
# enterprise-search is exposed on 3002 without SSL

###############################################################################################################

# configurable vars
HEAP="512m"

###############################################################################################################
# set WORKDIR
WORKDIR="${HOME}/elasticstack"

# colors
red=`tput setaf 1`
green=`tput setaf 2`
blue=`tput setaf 4`
reset=`tput sgr0`

###############################################################################################################

help() {
  echo -e "${green}Usage:${reset} ./`basename $0` command version"
  echo -e "\tThis script currently works on all 7.x and 6.x versions of elasticsearch"
  echo -e "\t${blue}COMMAND${reset}"
  echo -e "\t${blue}build${reset} - Starts deployment.  Must give the option of full version to deploy"
  echo -e "\t\tExample: ./`basename $0` build 7.10.2"
  echo -e "\t${blue}monitor${reset} - If deployment is already running it will add apm-server else it will deploy the stack first then enable metricbeat & filebeat. Only for version 6.5+"
  echo -e "\t\tExample: ./`basename $0` monitor 7.10.2"
  echo -e "\t${blue}snapshot${reset} - If deployment is already running it will add apm-server else it will deploy the stack first then enable minio server and snapshot repository.  For 7.4+ it will also setup SLM."
  echo -e "\t\tExample: ./`basename $0` snapshot 7.10.2"
  echo -e "\t${blue}full${reset} - Starts deployment with metricbeat & filebeat monitoring and minio with snapshots"
  echo -e "\t\tExample: ./`basename $0` full 7.10.2"
  echo -e "\t${blue}apm${reset} - If deployment is already running it will add apm-server else it will deploy the stack first then add apm-server"
  echo -e "\t\tExample: ./`basename $0` apm 7.10.2"
  echo -e "\t${blue}fullapm${reset} - Starts deployment with metricbeat & filebeat monitoring, snapshots, & apm-server"
  echo -e "\t\tExample: ./`basename $0` fullapm 7.10.2"
  echo -e "\t${blue}entsearch${reset} - If deployment is already running it will add apm-server else it will deploy the stack first then add Enterprise Search. Enterprise Search is only available on 7.7+"
  echo -e "\t\tExample: ./`basename $0` entsearch 7.10.2"
  echo -e "\t${blue}fullentsearch${reset} - Starts deployment with metricbeat & filebeat monitoring, snapshots, & Enterprise Search"
  echo -e "\t\tExample: ./`basename $0` fullentsearch 7.10.2"
  echo -e "\t${blue}all${reset} - Starts deployment with everything!"
  echo -e "\t\tExample: ./`basename $0` all 7.10.2"
  echo -e ""
  exit
}

###############################################################################################################

version() {
  # check for version and make sure its [6..8].x.x and assign MAJOR MINOR BUGFIX number
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

###############################################################################################################

checkmaxmapcount() {
  # check vm.max_map_count on linux and ask user to set it if not set properly
  if [ "`uname -s`" != "Darwin" ]; then
    COUNT=`sysctl vm.max_map_count | awk {' print $3 '}`
    if [ ${COUNT} -le "262144" ]; then
      echo "${green}[DEBUG]${reset} Ensuring vm.max_map_count is ${COUNT}... proceeding"
    else
      echo "${red}[DEBUG]${reset} vm.max_map_count needs to be set to 262144.  Please run sudo sysctl -w vm.max_map_count=262144"
      exit;
    fi
  fi
}

###############################################################################################################

checkdocker() {
  # check to ensure docker is running and you can run docker commands
  docker info >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${red}[DEBUG]${reset} Docker is not running or you are not part of the docker group"
    exit
  fi

  # check to ensure docker-compose is installed
  docker-compose version >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${red}[DEBUG]${reset} docker-compose is not installed.  Please install docker-compose and try again"
    exit
  fi
}

###############################################################################################################

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

###############################################################################################################

checkhealth() {
  # check to make sure that the deployment is in GREEN status
  if [ ${MAJOR} = "7" ] && [ ${MINOR} -ge "2" ]; then
    while true
    do
      if [ `docker run --rm -v es_certs:/certs --network=es_default docker.elastic.co/elasticsearch/elasticsearch:${VERSION} curl -s --cacert /certs/ca/ca.crt -u elastic:${PASSWD}   https://es01:9200/_cluster/health | grep -c green` = 1 ]; then
        sleep 2
        break
      else
        echo "${red}[DEBUG]${reset} elasticsearch is unhealthy. Checking again in 2 seconds.. if this doesnt finish in ~ 30 seconds something is wrong ctrl-c please."
        sleep 2
      fi
    done
  else
    while true
    do
      if [ `curl --cacert certs/ca/ca.crt -s -u elastic:${PASSWD} https://localhost:9200/_cluster/health | grep -c green` = 1 ]; then
        sleep 2
        break
      else
        echo "${red}[DEBUG]${reset} elasticsearch is unhealthy. Checking again in 2 seconds... if this doesnt finish in ~ 30 seconds something is wrong ctrl-c please."
        sleep 2
      fi
    done
  fi

  echo "${green}[DEBUG]${reset} elasticsearch health is ${green}GREEN${reset} moving forward."
}

###############################################################################################################

grabpasswd() {
  # grab the elastic password
  PASSWD=`cat notes | grep "PASSWORD elastic" | awk {' print $4 '}`
  if [ -z ${PASSWD} ]; then
    echo "${red}[DEBUG]${reset} unable to find elastic users password"
  	exit
  else
    echo "${green}[DEBUG]${reset} elastic user's password found ${PASSWD}"
  fi
}

###############################################################################################################

pullimage() {
  # checking for image
  docker image inspect "${1}" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${green}[DEBUG]${reset} Pulling "${1}" image... might take a while"
    docker pull "${1}"
    if [ $? -ne 0  ]; then
      echo "${red}[DEBUG]${reset} Unable to pull "${1}". "
      exit
    fi
  else
    echo "${green}[DEBUG]${reset} "${1}" docker image already exists.. moving forward.."
  fi
}

###############################################################################################################

cleanup() {
  # cleanup deployment
  echo "${green}********** Cleaning up "${VERSION}" **********${reset}"

  # check to see if the directory exists should not since this is the start
  STRING="-f stack-compose.yml"
  LIST="es01 es02 es03 kibana es_wait_until_ready_1"

  if [ -z ${WORKDIR} ]; then
    cd ${WORKDIR}

    if [ -f monitor-compose.yml ]; then
      STRING="${STRING} -f monitor-compose.yml"
      LIST="${LIST} metricbeat filebeat"
    fi

    if [ -f snapshot-compose.yml ]; then
      STRING="${STRING} -f snapshot-compose.yml"
      LIST="${LIST} minio01 es_mc_1"
    fi

    if [ -f apm-compose.yml ]; then
      STRING="${STRING} -f apm-compose.yml"
      LIST="${LIST} apm"
    fi

    if [ -f entsearch-compose.yml ]; then
      STRING="${STRING} -f entsearch-compose.yml"
      LIST="${LIST} entsearch"
    fi

    docker-compose ${STRING} down >/dev/null 2>&1
    echo "${green}[DEBUG]${reset} Performed docker-compose down"

  fi

  docker stop es01 es02 es03 kibana metricbeat filebeat apm entsearch minio01 es_mc_1 es_wait_until_ready_1 apm >/dev/null 2>&1
  docker rm es01 es02 es03 kibana metricbeat filebeat apm entsearch minio01 es_mc_1 es_wait_until_ready_1 apm >/dev/null 2>&1
  docker network rm es_default >/dev/null 2>&1
  docker volume rm es_data01 >/dev/null 2>&1
  docker volume rm es_data02 >/dev/null 2>&1
  docker volume rm es_data03 >/dev/null 2>&1
  docker volume rm es_certs >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} Removed volumes and networks"

  rm -rf ${WORKDIR} >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} All cleanedup"

}

###############################################################################################################

stack() {
  # building the stack
  VERSION=${1}
  version ${VERSION}

  echo "${green}********** Deploying elasticsearch & kibana "${VERSION}" **********${reset}"

  # some checks first
  checkmaxmapcount
  checkdocker
  checkcontainer

  # check to see if the directory exists should not since this is the start
  if [ -d ${WORKDIR} ]; then
    echo "${red}[DEBUG]${reset} Looks like ${WORKDIR} already exists.  Please run cleanup to delete the old deployment"
	exit
  fi

  # pull stack images
  pullimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
  pullimage "docker.elastic.co/kibana/kibana:${VERSION}"

  # create directorys and files
  mkdir -p ${WORKDIR}
  cd ${WORKDIR}
  mkdir temp
  echo ${VERSION} > VERSION

  # create elasticsearch.yml
  cat > elasticsearch.yml<<EOF
network.host: 0.0.0.0
EOF

  chown 1000 elasticsearch.yml >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} Created elasticsearch.yml"

  # generate temp elastic password
  PASSWD=`openssl rand -base64 29 | tr -d "=+/" | cut -c1-25`
  echo "${green}[DEBUG]${reset} Setting temp password for elastic as ${PASSWD}"

  # create temp kibana.yml
  cat > kibana.yml<<EOF
elasticsearch.username: "elstic"
elasticsearch.password: "${PASSWD}"
EOF

  echo "${green}[DEBUG]${reset} Created kibana.yml"

  # create env file
  cat > .env<<EOF
COMPOSE_PROJECT_NAME=es
CERTS_DIR=/usr/share/elasticsearch/config/certificates
KIBANA_CERTS_DIR=/usr/share/kibana/config/certificates
ELASTIC_PASSWORD=${PASSWD}
COMPOSE_HTTP_TIMEOUT=600
EOF

  echo "${green}[DEBUG]${reset} Created .env file"

  # create instances file
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

  - name: apm
    dns:
      - apm
      - localhost
    ip:
      - 127.0.0.1

  - name: entsearch
    dns:
      - entsearch
      - localhost
    ip:
      - 127.0.0.1

  - name: minio
    dns:
      - minio01
      - localhost
    ip:
      - 127.0.0.1
EOF

  echo "${green}[DEBUG]${reset} Created instances.yml"

  # start creating create-certs.yml
  createcertscurrent="version: '2.2'

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
    user: \"0\"
    working_dir: /usr/share/elasticsearch
    volumes: ['certs:/certs', '.:/usr/share/elasticsearch/config/certificates']

volumes: {"certs"}
networks:
  default:
    driver: bridge
    internal: true
  "

  createcerts71="version: '2.2'

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
    networks:
      default:
        driver: bridge
        internal: true

  "

    createcerts6="version: '2.2'

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
    networks:
      default:
        driver: bridge
        internal: true
  "

  if [ ${MAJOR} = "7" ] && [ ${MINOR} -ge "2" ]; then
    echo "${createcertscurrent}" > create-certs.yml
  else
    echo "${createcerts6}" > create-certs.yml
  fi
  echo "${green}[DEBUG]${reset} Created create-certs.yml for ${VERSION}"

  # create stack-compose.yml
  stackcomposecurrent="version: '2.2'

services:
  es01:
    container_name: es01
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es01
      - node.attr.data=hot
      - node.attr.data2=hot
      - node.attr.zone=zone1
      - node.attr.zone2=zone1
      - discovery.seed_hosts=es01,es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - ELASTIC_PASSWORD=${PASSWD}
      - \"ES_JAVA_OPTS=-Xms${HEAP} -Xmx${HEAP}\"
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
    labels:
      co.elastic.logs/module: elasticsearch
    volumes: ['data01:/usr/share/elasticsearch/data', 'certs:\$CERTS_DIR', './elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml', './temp:/temp']
    restart: on-failure
    ports:
      - 9200:9200
    healthcheck:
      test: curl --cacert \$CERTS_DIR/ca/ca.crt -s https://localhost:9200 >/dev/null; if [[ \$\$? == 52 ]]; then echo 0; else echo 1; fi
      interval: 30s
      timeout: 10s
      retries: 5

  es02:
    container_name: es02
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es02
      - node.attr.data=hot
      - node.attr.data2=warm
      - node.attr.zone=zone1
      - node.attr.zone2=zone2
      - discovery.seed_hosts=es01,es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - ELASTIC_PASSWORD=${PASSWD}
      - \"ES_JAVA_OPTS=-Xms${HEAP} -Xmx${HEAP}\"
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
    labels:
      co.elastic.logs/module: elasticsearch
    volumes: ['data02:/usr/share/elasticsearch/data', 'certs:\$CERTS_DIR', './elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml', './temp:/temp']
    restart: on-failure

  es03:
    container_name: es03
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es03
      - node.attr.data=warm
      - node.attr.data2=cold
      - node.attr.zone=zone2
      - node.attr.zone2=zone3
      - discovery.seed_hosts=es01,es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - ELASTIC_PASSWORD=${PASSWD}
      - \"ES_JAVA_OPTS=-Xms${HEAP} -Xmx${HEAP}\"
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
    labels:
      co.elastic.logs/module: elasticsearch
    volumes: ['data03:/usr/share/elasticsearch/data', 'certs:\$CERTS_DIR', './elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml', './temp:/temp']
    restart: on-failure

  kibana:
    container_name: kibana
    image: docker.elastic.co/kibana/kibana:${VERSION}
    environment:
      - SERVER_NAME=kibana
      - SERVER_HOST=\"0\"
      - ELASTICSEARCH_HOSTS=[\"https://es01:9200\",\"https://es02:9200\",\"https://es03:9200\"]
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
    restart: on-failure

  wait_until_ready:
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    command: /usr/bin/true
    depends_on: {\"es01\": {\"condition\": \"service_healthy\"}}

volumes: {\"data01\", \"data02\", \"data03\", \"certs\"}
networks:
  default:
    driver: bridge
    internal: true
  "

  stackcompose71="version: '2.2'

services:
  es01:
    container_name: es01
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es01
      - node.attr.data=hot
      - node.attr.data2=hot
      - node.attr.zone=zone1
      - node.attr.zone2=zone1
      - discovery.seed_hosts=es01,es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - ELASTIC_PASSWORD=${PASSWD}
      - \"ES_JAVA_OPTS=-Xms${HEAP} -Xmx${HEAP}\"
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
    labels:
      co.elastic.logs/module: elasticsearch
    volumes: ['data01:/usr/share/elasticsearch/data', './certs:\$CERTS_DIR', './elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml', './temp:/temp']
    restart: on-failure
    ports:
      - 9200:9200
    healthcheck:
      test: curl --cacert \$CERTS_DIR/ca/ca.crt -s https://localhost:9200 >/dev/null; if [[ \$\$? == 52 ]]; then echo 0; else echo 1; fi
      interval: 30s
      timeout: 10s
      retries: 5

  es02:
    container_name: es02
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es02
      - node.attr.data=hot
      - node.attr.data2=warm
      - node.attr.zone=zone1
      - node.attr.zone2=zone2
      - discovery.seed_hosts=es01,es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - ELASTIC_PASSWORD=${PASSWD}
      - \"ES_JAVA_OPTS=-Xms${HEAP} -Xmx${HEAP}\"
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
    labels:
      co.elastic.logs/module: elasticsearch
    volumes: ['data02:/usr/share/elasticsearch/data', './certs:\$CERTS_DIR', './elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml', './temp:/temp']
    restart: on-failure

  es03:
    container_name: es03
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es03
      - node.attr.data=warm
      - node.attr.data2=cold
      - node.attr.zone=zone2
      - node.attr.zone=zone3
      - discovery.seed_hosts=es01,es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - ELASTIC_PASSWORD=${PASSWD}
      - \"ES_JAVA_OPTS=-Xms${HEAP} -Xmx${HEAP}\"
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
    labels:
      co.elastic.logs/module: elasticsearch
    volumes: ['data03:/usr/share/elasticsearch/data', './certs:\$CERTS_DIR', './elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml', './temp:/temp']
    restart: on-failure

  kibana:
    container_name: kibana
    image: docker.elastic.co/kibana/kibana:${VERSION}
    environment:
      - SERVER_NAME=kibana
      - SERVER_HOST=\"0\"
      - ELASTICSEARCH_HOSTS=[\"https://es01:9200\",\"https://es02:9200\",\"https://es03:9200\"]
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
    restart: on-failure

  wait_until_ready:
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    command: /usr/bin/true
    depends_on: {\"es01\": {\"condition\": \"service_healthy\"}}

volumes: {\"data01\", \"data02\", \"data03\", \"certs\"}
networks:
  default:
    driver: bridge
    internal: true
  "

  stackcompose6="version: '2.2'

services:
  es01:
    container_name: es01
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es01
      - node.attr.data=hot
      - node.attr.data2=hot
      - node.attr.zone=zone1
      - node.attr.zone2=zone1
      - cluster.name=docker-cluster
      - discovery.zen.minimum_master_nodes=2
      - discovery.zen.ping.unicast.hosts=es01,es02,es03
      - ELASTIC_PASSWORD=${PASSWD}
      - \"ES_JAVA_OPTS=-Xms${HEAP} -Xmx${HEAP}\"
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
    volumes: ['data01:/usr/share/elasticsearch/data', './certs:\$CERTS_DIR', './elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml', './temp:/temp']
    ports:
      - 9200:9200
    restart: on-failure
    healthcheck:
      test: curl --cacert \$CERTS_DIR/ca/ca.crt -s https://localhost:9200 >/dev/null; if [[ \$\$? == 52 ]]; then echo 0; else echo 1; fi
      interval: 30s
      timeout: 10s
      retries: 25

  es02:
    container_name: es02
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es02
      - node.attr.data=hot
      - node.attr.data2=warm
      - node.attr.zone=zone1
      - node.attr.zone2=zone2
      - cluster.name=docker-cluster
      - discovery.zen.minimum_master_nodes=2
      - ELASTIC_PASSWORD=${PASSWD}
      - discovery.zen.ping.unicast.hosts=es01,es02,es03
      - \"ES_JAVA_OPTS=-Xms${HEAP} -Xmx${HEAP}\"
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
    volumes: ['data02:/usr/share/elasticsearch/data', './certs:\$CERTS_DIR', './elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml', './temp:/temp']
    restart: on-failure

  es03:
    container_name: es03
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es03
      - node.attr.data=warm
      - node.attr.data2=cold
      - node.attr.zone=zone2
      - node.attr.zone2=zone3
      - cluster.name=docker-cluster
      - discovery.zen.minimum_master_nodes=2
      - ELASTIC_PASSWORD=${PASSWD}
      - discovery.zen.ping.unicast.hosts=es01,es02,es03
      - \"ES_JAVA_OPTS=-Xms${HEAP} -Xmx${HEAP}\"
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
    volumes: ['data03:/usr/share/elasticsearch/data', './certs:\$CERTS_DIR', './elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml', './temp:/temp']
    restart: on-failure

  wait_until_ready:
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    command: /usr/bin/true
    depends_on: {\"es01\": {\"condition\": \"service_healthy\"}}

  kibana:
    container_name: kibana
    image: docker.elastic.co/kibana/kibana:${VERSION}
    environment:
      - SERVER_NAME=kibana
      - SERVER_HOST=\"0\"
      - ELASTICSEARCH_HOSTS=[\"https://es01:9200\",\"https://es02:9200\",\"https://es03:9200\"]
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
    restart: on-failure

volumes: {\"data01\", \"data02\", \"data03\" , \"certs\"}
networks:
  default:
    driver: bridge
    internal: true
  "

  if [ ${MAJOR} = "7" ] && [ ${MINOR} -ge "2" ]; then
    echo "${stackcomposecurrent}" > stack-compose.yml
  elif [ ${MAJOR} = "7" ] && [ ${MINOR} -le "1" ]; then
    echo "${stackcompose71}" > stack-compose.yml
  else
    echo "${stackcompose6}" > stack-compose.yml
    if [ ${MAJOR} = "6" ] && [ ${MINOR} -le "5" ]; then
      if [ "`uname -s`" != "Darwin" ]; then
        sed -i 's/ELASTICSEARCH_HOSTS.*/ELASTICSEARCH_URL=https:\/\/es01:9200/g' stack-compose.yml
      else
        sed -i '' -E 's/ELASTICSEARCH_HOST.*/ELASTICSEARCH_URL=https:\/\/es01:9200/g' stack-compose.yml
      fi
    fi
  fi
  echo "${green}[DEBUG]${reset} Created stack-compose.yml for ${VERSION}"

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
      docker exec es01 /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch \
--url https://localhost:9200" | tee -a notes
    else
      docker exec es01 /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch \
-Expack.security.http.ssl.certificate=certificates/es01/es01.crt \
-Expack.security.http.ssl.certificate_authorities=certificates/ca/ca.crt \
-Expack.security.http.ssl.key=certificates/es01/es01.key \
--url https://localhost:9200" | tee -a notes
    fi
  elif [ ${MAJOR} = "6" ]; then
    docker exec es01 /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch \
-Expack.security.http.ssl.certificate_authorities=certificates/ca/ca.crt \
--url https://localhost:9200" | tee -a notes
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
  echo "${green}[DEBUG]${reset} kibana.yml re-generated with new password and encryption keys"

  # restart kibana
  docker restart kibana >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} Restarted kibana to pick up the new elastic password"

  # copy the certificate authority into the homedir for the project
  if [ ${MAJOR} = "7" ] && [ ${MINOR} -ge "2" ]; then
    docker exec es01 /bin/bash -c "cp /usr/share/elasticsearch/config/certificates/ca/ca.* /temp/"
    mv ${WORKDIR}/temp/ca.* ${WORKDIR}/
  else
    cp ${WORKDIR}/certs/ca/ca.* ${WORKDIR}/
  fi
  echo "${green}[DEBUG]${reset} Copied the certificate authority into ${WORKDIR}"

  echo "${green}[DEBUG]${reset} Complete! - stack deployed. ${VERSION} "
  echo ""

# End of stack function
}

###############################################################################################################

monitor() {
  # adding monitoring
  VERSION=${1}
  version ${VERSION}

  # check to make sure that ES is 6.6 or greater
  if [ ${MAJOR} = "6" ]  && [ ${MINOR} -le "4" ]; then
    echo "${red}[DEBUG]${reset} metricbeats collections started with 6.5+.  Please use legacy collections method"
    return
  else
    echo "${green}********** Deploying metricbeat collections monitoring **********${reset}"
  fi

  # check to see if ${WORKDIR} exits
  if [ ! -d ${WORKDIR} ]; then
    echo "${red}[DEBUG]${reset} Deployment does not exist.  Starting deployment first"
    stack ${VERSION}
  else
    cd ${WORKDIR}
  fi

  # check to see if monitor-compose.yml already exists.
  if [ -f "monitor-compose.yml" ]; then
    echo "${red}[DEBUG]${reset} monitor-compose.yml already exists. Exiting."
    return
  fi

  # check to see if version match
  OLDVERSION="`cat VERSION`"
  if [ "${OLDVERSION}" != "${VERSION}" ]; then
    echo "${red}[DEBUG]${reset} Version installed is ${OLDVERSION} however you requested monitoring for ${VERSION}"
    return
  fi

    # grab the elastic password
    grabpasswd

    checkhealth

  # add MB_CERTS_DIR & FB_CERTS to .env
  cat >> .env<<EOF
MB_CERTS_DIR=/usr/share/metricbeat/certificates
FB_CERTS_DIR=/usr/share/filebeat/certificates
EOF

  echo "${green}[DEBUG]${reset} Adding MB_CERTS_DIR & FB_CERTS_DIR to .env"

  # pull images
  pullimage "docker.elastic.co/beats/metricbeat:${VERSION}"
  pullimage "docker.elastic.co/beats/filebeat:${VERSION}"

  # add xpack.monitoring.kibana.collection.enabled: false to kibana.yml and restart kibana
  echo "xpack.monitoring.kibana.collection.enabled: false" >> kibana.yml
  docker restart kibana >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${red}[DEBUG]${reset} Unable to restart kibana"
    exit
  else
    echo "${green}[DEBUG]${reset} kibana restarted after adding xpack.monitoring.kibana.collection.enabled: false"
    sleep 2
  fi

    common7="# common
http.enabled: true
http.port: 5066
http.host: 0.0.0.0

processors:
  - add_cloud_metadata: ~
  - add_docker_metadata: ~

monitoring.enabled: false

output.elasticsearch:
  hosts: [\"https://es01:9200\", \"https://es02:9200\", \"https://es03:9200\"]
  username: \"elastic\"
  password: "\"${PASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]

metricbeat.modules:
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
  "
  common6="# common
http.enabled: true
http.port: 5066
http.host: 0.0.0.0

processors:
  - add_cloud_metadata: ~
  - add_docker_metadata: ~

output.elasticsearch:
  hosts: [\"https://es01:9200\", \"https://es02:9200\", \"https://es03:9200\"]
  username: \"elastic\"
  password: "\"${PASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: none
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]

metricbeat.modules:
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
  ssl.verification_mode: none
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]

  "

  beats="# Module: beats
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

  "

  escurrent="# Module: elasticsearch
- module: elasticsearch
  xpack.enabled: true
  period: 10s
  hosts: [\"https://es01:9200\", \"https://es02:9200\", \"https://es03:9200\"]
  username: \"elastic\"
  password: "\"${PASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]

  "

  es78="# Module: elasticsearch
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
  "

  es74="# Module: elasticsearch
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
  "

  if [ ${MAJOR} = "7" ]; then
    echo "${common7}" > metricbeat.yml
    if [ ${MINOR} -ge "3" ]; then
      echo "${beats}" >> metricbeat.yml
    fi
    if [ ${MINOR} -ge "9" ]; then
      echo "${escurrent}" >> metricbeat.yml
    elif [ ${MINOR} -ge "5" ]; then
      echo "${es78}" >> metricbeat.yml
    elif [ ${MINOR} -ge "2" ]; then
      echo "${es74}" >> metricbeat.yml
    else
      echo "${es74}" >> metricbeat.yml
      if [ "`uname -s`" != "Darwin" ]; then
        sed -i 's/full/none/g' metricbeat.yml
      else
        sed -i '' -E 's/full/none/g' metricbeat.yml
      fi
    fi
  elif [ ${MAJOR} = "6" ]; then
    echo "${common6}" > metricbeat.yml
    echo "${es74}" >> metricbeat.yml
    if [ "`uname -s`" != "Darwin" ]; then
      sed -i 's/full/none/g' metricbeat.yml
    else
        sed -i '' -E 's/full/none/g' metricbeat.yml
    fi
  fi
  chmod go-w metricbeat.yml >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} Created metricbeat.yml"

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

  if [ ${MAJOR} = "7" ]; then
    if [ ${MINOR} -le "1" ]; then
      if [ "`uname -s`" != "Darwin" ]; then
        sed -i 's/full/none/g' filebeat.yml
      else
        sed -i '' -E 's/full/none/g' filebeat.yml
      fi
    fi
  elif [ ${MAJOR} = "6" ]; then
    if [ "`uname -s`" != "Darwin" ]; then
      sed -i 's/full/none/g' filebeat.yml
    else
      sed -i '' -E 's/full/none/g' filebeat.yml
    fi
  fi
  echo "${green}[DEBUG]${reset} Created filebeat.yml"

  if [ ${MAJOR} = "7" ] && [ ${MINOR} -ge "7" ]; then
    STRINGMB="command: metricbeat -environment container --strict.perms=false"
    STRINGFB="command: filebeat -environment container --strict.perms=false"
  else
    STRINGMB="command: metricbeat -e --strict.perms=false"
    STRINGFB="command: filebeat -e --strict.perms=false"
  fi

  cat > monitor-compose.yml<<EOF
version: '2.2'

services:
  metricbeat:
    container_name: metricbeat
    user: root
    ${STRINGMB}
    image: docker.elastic.co/beats/metricbeat:${VERSION}
    volumes: ['./metricbeat.yml:/usr/share/metricbeat/metricbeat.yml', 'certs:\$MB_CERTS_DIR', './temp:/temp', '/var/run/docker.sock:/var/run/docker.sock:ro']
    restart: on-failure
  filebeat:
    container_name: filebeat
    user: root
    ${STRINGFB}
    image: docker.elastic.co/beats/filebeat:${VERSION}
    volumes: ['./filebeat.yml:/usr/share/filebeat/filebeat.yml', 'certs:\$FB_CERTS_DIR', './temp:/temp', '/var/lib/docker/containers:/var/lib/docker/containers:ro', '/var/run/docker.sock:/var/run/docker.sock:ro']
    restart: on-failure

volumes: {"certs"}
EOF

  if [ ${MAJOR} = "7" ] && [ ${MINOR} -ge "2" ]; then
    true
  else
    if [ "`uname -s`" != "Darwin" ]; then
      sed -i 's/certs/\.\/certs/g' monitor-compose.yml
      sed -i 's/^volumes.*//g' monitor-compose.yml
    else
      sed -i '' -E 's/certs/\.\/certs/g' monitor-compose.yml
      sed -i '' -E 's/^volumes.*//g' monitor-compose.yml
    fi
  fi

  echo "${green}[DEBUG]${reset} Created monitor-compose.yml"

  # add setting for xpack.monitoring.collection.enabled
  checkhealth

  echo "${green}[DEBUG]${reset} Setting xpack.monitoring.collection.enabled: true"
  curl -k -u elastic:${PASSWD} -X PUT "https://localhost:9200/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "xpack.monitoring.collection.enabled": true,
    "xpack.monitoring.elasticsearch.collection.enabled": false
  }
}
' >/dev/null 2>&1

  # add monitoring for APM if metricbeat.yml exists
  if [ -f apm-server.yml ] && [ -f metricbeat.yml ]; then
    if [ "`uname -s`" != "Darwin" ]; then
      sed -i 's/filebeat:5066"/filebeat:5066", "http:\/\/apm:5066"/g' metricbeat.yml
    else
      sed -i '' -E 's/filebeat:5066"/filebeat:5066", "http:\/\/apm:5066"/g' metricbeat.yml
    fi
    echo "${green}[DEBUG]${reset} Found APM-SERVER adding to beats monitoring"
  fi

  # start service
  echo "${green}[DEBUG]${reset} Starting monitoring....."
  docker-compose -f monitor-compose.yml up -d >/dev/null 2>&1

# End of monitor function
}

###############################################################################################################

snapshot() {
  # adding monitoring
  VERSION=${1}
  version ${VERSION}

  # check to see if ${WORKDIR} exits
  if [ ! -d ${WORKDIR} ]; then
    echo "${red}[DEBUG]${reset} Deployment does not exist.  Starting deployment first"
    stack ${VERSION}
    echo "${green}********** Deploying minio and snapshots **********${reset}"
  else
    cd ${WORKDIR}
    echo "${green}********** Deploying minio and snapshots **********${reset}"
  fi

  # check to see if snapshot-compose.yml already exists.
  if [ -f "snapshot-compose.yml" ]; then
    echo "${red}[DEBUG]${reset} snapshot-compose.yml already exists. Exiting."
    return
  fi

  # check to see if version match
  OLDVERSION="`cat VERSION`"
  if [ "${OLDVERSION}" != "${VERSION}" ]; then
    echo "${red}[DEBUG]${reset} Version installed is ${OLDVERSION} however you requested snapshot for ${VERSION}"
    return
  fi

  # grab the elastic password
  grabpasswd

  # check health before continuing
  checkhealth

  # pull image
  pullimage "minio/minio:latest"

  # make data directory
  mkdir ${WORKDIR}/data

  # Set UG
  # UG="`$(id -u)`:`$(id -g)`"
  UG="$(id -u):$(id -g)"

  # create snapshot-compose.yml
  cat > snapshot-compose.yml<<EOF
version: '2.2'

services:
  minio01:
    container_name: minio01
    image: minio/minio
    user: "${UG}"
    environment:
      - MINIO_ROOT_USER=minio
      - MINIO_ROOT_PASSWORD=minio123
    volumes: ['./data:/data', './temp:/temp']
    command: server /data
    ports:
      - 9000:9000
    restart: on-failure
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
  docker-compose -f snapshot-compose.yml up -d >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${red}[DEBUG]${reset} Unable to start minio contianer"
    exit
  else
    echo "${green}[DEBUG]${reset} minio01 container deployed"
  fi

  # find docker IP for minio01
  IP=`docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' minio01`

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
      echo "${green}[DEBUG]${reset} 6.x found adding -Des.allow_insecure_Settings=true in jvm.options"
    fi
    docker restart ${instance} >/dev/null 2>&1
    echo "${green}[DEBUG]${reset} Restarted ${instance} after plugin and other changes"
    sleep 7
  done

  checkhealth

  # add repsitory
  if [ ${MAJOR} = "7" ]; then
    curl -k -u elastic:${PASSWD} -XPUT "https://localhost:9200/_snapshot/minio01" -H 'Content-Type: application/json' -d'
{
  "type" : "s3",
  "settings" : {
    "bucket" : "elastic",
    "client" : "minio01",
    "endpoint": "'${IP}':9000",
    "protocol": "http",
    "path_style_access" : "true"
  }
}' >/dev/null 2>&1

    echo "${green}[DEBUG]${reset} Added minio01 snapshot repository"

    if [ ${MINOR} -ge "4" ]; then
      curl -k -u elastic:${PASSWD} -XPUT "https://localhost:9200/_slm/policy/minio-snapshot-policy" -H 'Content-Type: application/json' -d'{  "schedule": "0 */30 * * * ?",   "name": "<minio-snapshot-{now/d}>",   "repository": "minio01",   "config": {     "partial": true  },  "retention": {     "expire_after": "5d",     "min_count": 1,     "max_count": 20   }}' >/dev/null 2>&1
      echo "${green}[DEBUG]${reset} Added minio-snapshot-policy"
      sleep 3
      curl -k -u elastic:${PASSWD} -XPUT "https://localhost:9200/_slm/policy/minio-snapshot-policy/_execute" >/dev/null 2>&1
      echo "${green}[DEBUG]${reset} Executed minio-snapshot-policy"
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
}' >/dev/null 2>&1

    echo "${green}[DEBUG]${reset} Added minio01 snapshot repository"
  fi

  # End of snapshot function
}

###############################################################################################################

apm() {
  # adding monitoring
  VERSION=${1}
  version ${VERSION}

  # check to see if ${WORKDIR} exits
  if [ ! -d ${WORKDIR} ]; then
    echo "${red}[DEBUG]${reset} Deployment does not exist.  Starting deployment first"
    stack ${VERSION}
    echo "${green}********** Deploying apm-server **********${reset}"
  else
    cd ${WORKDIR}
    echo "${green}********** Deploying apm-server **********${reset}"
  fi

  # check to see if apm-compose.yml already exists.
  if [ -f "apm-compose.yml" ]; then
    echo "${red}[DEBUG]${reset} apm-compose.yml already exists. Exiting."
    return
  fi

  # check to see if version match
  OLDVERSION="`cat VERSION`"
  if [ "${OLDVERSION}" != "${VERSION}" ]; then
    echo "${red}[DEBUG]${reset} Version installed is ${OLDVERSION} however you requested snapshot for ${VERSION}"
    return
  fi

  # grab the elastic password
  grabpasswd

  # check health before continuing
  checkhealth

  # pull image
  pullimage "docker.elastic.co/apm/apm-server:${VERSION}"

  # add APM_CERTS_DIR to .env
  cat >> .env<<EOF
APM_CERTS_DIR=/usr/share/apm-server/certificates
EOF


  # create apm-server.yml
  cat > apm-server.yml<<EOF
apm-server:
host: "0.0.0.0:8200"

ssl:
  enabled: false
  certificate: '/usr/share/apm-server/certificates/apm/apm.crt'
  key: '/usr/share/apm-server/certificates/apm/apm.key'

kibana:
  enabled: true
  host: "kibana:5601"
  protocol: "https"
  username: "elastic"
  password: "${PASSWD}"
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: ["/usr/share/apm-server/certificates/ca/ca.crt"]

output.elasticsearch:
  hosts: ["https://es01:9200", "https://es02:9200", "https://es03:9200"]
  enabled: true
  protocol: "https"
  username: "elastic"
  password: "${PASSWD}"
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: ["/usr/share/apm-server/certificates/ca/ca.crt"]

http.enabled: true
http.host: 0.0.0.0
http.port: 5066
EOF

  echo "${green}[DEBUG]${reset} apm-server.yml created"

  if [ ${MAJOR} = "7" ] && [ ${MINOR} -ge "7" ]; then
    STRINGAPM="command: apm-server -environment container --strict.perms=false"
  else
    STRINGAPM="command: apm-server -e --strict.perms=false"
  fi

  apm7="version: '2.2'

services:
  apm:
    container_name: apm
    image: docker.elastic.co/apm/apm-server:${VERSION}
    ${STRINGAPM}
    volumes: ['certs:\$APM_CERTS_DIR', './apm-server.yml:/usr/share/apm-server/apm-server.yml', './temp:/temp']
    ports:
      - 8200:8200
    restart: on-failure

volumes: {\"certs\"}
  "

  apm6="version: '2.2'

services:
  apm:
    container_name: apm
    image: docker.elastic.co/apm/apm-server:${VERSION}
    ${STRINGAPM}
    volumes: ['./certs:\$APM_CERTS_DIR', './apm-server.yml:/usr/share/apm-server/apm-server.yml', './temp:/temp']
    ports:
      - 8200:8200
    restart: on-failure
  "

  if [ ${MAJOR} = "7" ] && [ ${MINOR} -ge "2" ]; then
    echo "${apm7}" > apm-compose.yml
  else
    echo "${apm6}" > apm-compose.yml
  fi

  # starting APM
  docker-compose -f apm-compose.yml up -d >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${red}[DEBUG]${reset} Unable to start APM"
    return
  else
    echo "${green}[DEBUG]${reset} APM started"
  fi

  # add monitoring for APM if metricbeat.yml exists
  if [ -f metricbeat.yml ]; then
    if [ "`uname -s`" != "Darwin" ]; then
      sed -i 's/filebeat:5066"/filebeat:5066", "http:\/\/apm:5066"/g' metricbeat.yml
    else
      sed -i '' -E 's/filebeat:5066"/filebeat:5066", "http:\/\/apm:5066"/g' metricbeat.yml
    fi
    docker restart metricbeat >/dev/null 2>&1
    echo "${green}[DEBUG]${reset} added apm monitoring and restarted metricbeat"
  fi

  # End of apm function
}

###############################################################################################################

entsearch() {
  # adding monitoring
  VERSION=${1}
  version ${VERSION}

  # check to make sure that ES is 7.7 or greater
  if [ ${MAJOR} = "7" ]  && [ ${MINOR} -le "7" ]; then
    echo "${red}[DEBUG]${reset} Enterprise Search started with 7.7+."
    return
  fi

  # check to see if ${WORKDIR} exits
  if [ ! -d ${WORKDIR} ]; then
    echo "${red}[DEBUG]${reset} Deployment does not exist.  Starting deployment first"
    stack ${VERSION}
    echo "${green}********** Deploying Enterprise Search **********${reset}"
  else
    cd ${WORKDIR}
    echo "${green}********** Deploying Enterprise Search **********${reset}"
  fi

  # check to see if apm-compose.yml already exists.
  if [ -f "entsearch-compose.yml" ]; then
    echo "${red}[DEBUG]${reset} entsearch-compose.yml already exists. Exiting."
    return
  fi

  # check to see if version match
  OLDVERSION="`cat VERSION`"
  if [ "${OLDVERSION}" != "${VERSION}" ]; then
    echo "${red}[DEBUG]${reset} Version installed is ${OLDVERSION} however you requested snapshot for ${VERSION}"
    return
  fi

  # grab the elastic password
  grabpasswd

  # check health before continuing
  checkhealth

  # pull image
  pullimage "docker.elastic.co/enterprise-search/enterprise-search:${VERSION}"

  # generate kibana encryption key
  ENCRYPTION_KEY=`openssl rand -base64 40 | tr -d "=+/" | cut -c1-32`

  # add to .env
  cat >> .env<<EOF
ENTSEARCH_CERTS_DIR=/usr/share/enterprise-search/config/certificates
EOF
  # add to elasticsearch.yml
  cat >> elasticsearch.yml<<EOF
xpack.security.authc.api_key.enabled: true
action.auto_create_index: ".ent-search-*-logs-*,-.ent-search-*,-test-.ent-search-*,+*"
EOF

  # add to kibana.yml
  if [ ${MAJOR} = "7" ] && [ ${MINOR} -ge "10" ]; then
    cat >> kibana.yml<<EOF
enterpriseSearch.host: "http://localhost:3002"
EOF
  fi

  # restart elasticsearch
  for instance in es01 es02 es03 kibana
  do
    docker restart ${instance}>/dev/null 2>&1
    echo "${green}[DEBUG]${reset} Restarting ${instance} for Enterprise Search"
  done

  checkhealth

  # create enterprise-search.yml
  cat > enterprise-search.yml<<EOF
elasticsearch.host: https://es01:9200
elasticsearch.ssl.enabled: true
elasticsearch.ssl.certificate_authority: /usr/share/enterprise-search/config/certificates/ca/ca.crt

elasticsearch.username: elastic
elasticsearch.password: ${PASSWD}

ent_search.auth.default.source: standard
ent_search.ssl.enabled: false

ent_search.listen_host: 0.0.0.0
ent_search.listen_port: 3002
ent_search.external_url: http://localhost:3002

filebeat_log_directory: /var/log/enterprise-search
log_directory: /var/log/enterprise-search
secret_management.encryption_keys: [${ENCRYPTION_KEY}]
EOF

  echo "${green}[DEBUG]${reset} Created enterprise-search.yml"

  # generate entsearch-compose.yml
  cat > entsearch-compose.yml<<EOF
version: '2.2'

services:
  entsearch:
    container_name: entsearch
    image: docker.elastic.co/enterprise-search/enterprise-search:${VERSION}
    environment:
      - "ENT_SEARCH_DEFAULT_PASSWORD=${PASSWD}"
    volumes: ['./enterprise-search.yml:/usr/share/enterprise-search/config/enterprise-search.yml', 'certs:\$ENTSEARCH_CERTS_DIR', './temp:/temp']
    ports:
      - 3002:3002
    restart: on-failure

volumes: {"certs"}
EOF

  echo "${green}[DEBUG]${reset} Created entsearch-compose.yml"

  docker-compose -f entsearch-compose.yml up -d >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} Started Enterprise Search.  It takes a while to finish install. Please run docker logs -f entsearch to view progress"
  echo "${green}[DEBUG]${reset} For now please browse to http://IP:3002 and use enterprise_search and ${PASSWD} to login"
  echo "${green}[DEBUG]${reset} If you are redirected to http://localhost:3002 then edit elasticstack/enterprise-search.yml and change ent_search.external_url: http://localhost:3002 to localhost to your IP"

  # End of Enterprise Search
}

###############################################################################################################

case ${1} in
  build|start|stack)
    stack ${2}
    ;;
  monitor)
    monitor ${2}
    ;;
  snapshot)
    snapshot ${2}
    ;;
  apm)
    apm ${2}
    ;;
  entsearch)
    entsearch ${2}
    ;;
  full)
    stack ${2}
    monitor ${2}
    snapshot ${2}
    ;;
  fullapm)
    stack ${2}
    monitor ${2}
    snapshot ${2}
    apm ${2}
    ;;
  fullentsearch)
    stack ${2}
    monitor ${2}
    snapshot ${2}
    entsearch ${2}
    ;;
  all)
    stack ${2}
    monitor ${2}
    snapshot ${2}
    apm ${2}
    entsearch ${2}
    ;;
  cleanup)
    cleanup
    ;;
  *)
    help
    ;;
esac

exit # have a great day!
