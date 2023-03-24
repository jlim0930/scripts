#!/usr/bin/env bash

# justin lim <justin@isthecoolest.ninja>
# version 9.0 - added ldap & frozen tier
# version 8.0 - added fleet settings
# version 7.0 - added ES 8 only
# version 6.2 - changed the way fleet is bootstrapped
# version 6.1 - added additional functions and cleaned up
# version 5.0 - added fleet
# version 4.0 - added apm-server & enterprise search(still needs some work on es but its functional)
# version 3.0 - added minio & snapshots
# version 2.0 - added monitoring option
# version 1.0 - 3 node deployment with kibana

# $ curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/deploy-elastic.sh -o deploy-elastic.sh

# es01 is exposed on 9200 with SSL
# es02 is exposed on 9201 without SSL ( only for < 8.0.0 )
# kibana is exposed on 5601 with SSL
# enterprise-search is exposed on 3002 without SSL
# fleet is exposed on 8220

###############################################################################################################

# configurable vars
HEAP="512m"

###############################################################################################################

# set WORKDIR
WORKDIR="${HOME}/elasticstack"

###############################################################################################################

# colors
red=`tput setaf 1`
green=`tput setaf 2`
blue=`tput setaf 14`
reset=`tput sgr0`

###############################################################################################################

# help function
help()
{
  echo "${green}This script currently works on all versions of elasticsearch 6.x-8.x${reset}"
  echo ""
  echo "${green}Usage:${reset} ./`basename $0` command version"
  echo ""
  echo "${blue}COMMANDS:${reset}"
  echo "     ${green}stack|build|start${reset} - will stand up a basic elasticsearch 3 node cluster and 1 kibana"
  echo "     ${green}monitor${reset} - will stand up a stack with metricbeats monitoring"
  echo "     ${green}snapshot${reset} - will stand up a stack with minio (http) as snapshot repository"
  echo "     ${green}fleet${reset} - will stand up a stack wtih a fleet server"
  echo "     ${green}ldap${reset} - will stand up a stack wtih an LDAP server and configures realm"
  echo "     ${green}entsearch${reset} - will stand up a stack with enterprise search"
  echo "     ${green}apm${reset} - will stand up a stack with apmserver"
  echo ""
  echo "     ${green}cleanup${reset} - cleanup the deployment and delete it and all of its resources minus images"
  echo ""
  echo "Each ${blue}command${reset} is additive, if you stood up a basic stack and want to add on monitoring just run the ${blue}command${reset} again with COMMAND as monitor and it will add it to the same stack"
  echo ""
  echo "${blue}MATRIX${reset}"
  fmt="%20s %10s %10s %10s\n"
  printf "$fmt" "" "6.x" "7.x" "8.x"
  printf "$fmt" "elasticstack" "*" "*" "*"
  printf "$fmt" "monitoring" "6.5.0+" "*" "*"
  printf "$fmt" "snapshot" "*" "*" "*"
  printf "$fmt" "fleet" "x" "7.10.0+" "*"
  printf "$fmt" "enterprise search" "x" "7.7.0+" "*"
  printf "$fmt" "apm server" "*" "-7.16.0" "x"
  echo ""
  echo "apm server was moved to fleet integrations starting 7.16.0 - Please use fleet"
  echo ""
  echo "If running locally after the stack is deployed you can grab all the passwords from ~/elasticstack/notes"
  echo "To access kibana browse to https://localhost:5601, if remotely https://IPofREMOTEhost:5601"
  echo ""
} # end of help function

###############################################################################################################

# functions

# spinner
spinner() {
  local PROC="${1}"

  tput civis

  # Clear Line
  CL="\e[2K"
  # Spinner Character
  SPINNER="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

  while [ $(ps -ef | grep -c ${PROC}) -ge 2 ]; do
    for (( i=0; i<${#SPINNER}; i++ )); do
      sleep 0.05
      printf "${CL}${SPINNER:$i:1} ${2}\r"
    done
  done

  tput cnorm
} # end spinner

# check for version and make sure its [6..8].x.x and assign MAJOR MINOR BUGFIX number
version() {
  if [ -z ${1} ]; then
    help
    exit
  else
    re="^[6-8]{1}[.][0-9]{1,2}[.][0-9]{1,2}$"
    if [[ ${1} =~ ${re} ]]; then
      MAJOR="$(echo ${1} | awk -F. '{ print $1 }')"
      MINOR="$(echo ${1} | awk -F. '{ print $2 }')"
      BUGFIX="$(echo ${1} | awk -F. '{ print $3 }')"
    else
      help
      exit
    fi
  fi
} # end of version function

# function used for version checking and comparing
checkversion() {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
} # end of checkversion function

# check vm.max_map_count on linux and ask user to set it if not set properly
checkmaxmapcount() {
  if [ "`uname -s`" != "Darwin" ]; then
    COUNT=`sysctl vm.max_map_count | awk {' print $3 '}`
    if [ ${COUNT} -le "262144" ]; then
      echo "${green}[DEBUG]${reset} Ensuring vm.max_map_count is ${COUNT}... proceeding"
    else
      echo "${red}[DEBUG]${reset} vm.max_map_count needs to be set to 262144.  Please run sudo sysctl -w vm.max_map_count=262144"
      exit
    fi
  fi
} # end of checkmaxmapcount function

# check to ensure docker is running and you can run docker commands
checkdocker() {
  # check to ensure docker is installed or exit
  docker info >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${red}[DEBUG]${reset} Docker is not running or you are not part of the docker group"
    exit
  fi

  # check to ensure docker-compose is installed or exit
  docker-compose version >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${red}[DEBUG]${reset} docker-compose is not installed.  Please install docker-compose and try again"
    exit
  fi

  # check to ensure jq is installed or exit
  if ! [ -x "$(command -v jq)" ]; then
    echo "${red}[DEBUG]${reset} jq is not installed.  Please install jq and try again"
    exit
  fi

} # end of checkdocker function

# check to see if containers/networks/volumes exists
checkcontainer() {
  for name in es01 es02 es03 kibana es_mc_1 es_wait_until_ready_1 apm es_setup_1
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
  for name in es_data01 es_data02 es_data03 es_certs es_fleet es_certs es_kibanadata
  do
    if [ $(docker volume ls --format '{{.Name}}' | grep -c ${name}) -ge 1 ]; then
      echo "${red}[DEBUG]${reset} Volume ${green}${name}${reset} exists.  Please remove and try again"
      exit
    fi
  done
} # end of checkcontainer function

checkhealth() {
  echo ""
  until [ $(curl -s --cacert ${WORKDIR}/ca.crt -u elastic:${PASSWD} https://localhost:9200/_cluster/health | grep -c green) -eq 1 ]; do
    sleep 2
  done &
  spinner $! "${blue}[DEBUG]${reset} Checking cluster health.  If this does not finish in ~ 1 minute something is wrong." 
  echo ""
}

checkfleet() {
  echo ""
  until [ $(curl -f -s -k https://localhost:8220/api/status | grep -c HEALTHY) -eq 1 ]; do
    sleep 2
  done &
  spinner $! "${blue}[DEBUG]${reset} Checking fleet server health.  If this does not finish in ~ 1 minute something is wrong." 
  echo ""
}

# grab the elastic password
grabpasswd() {
  if [ $(checkversion $VERSION) -ge $(checkversion "8.0.0") ]; then
    PASSWD=`cat notes | grep ELASTIC_PASSWORD | awk -F"=" {' print $2 '}`
  else
    PASSWD=`cat notes | grep "PASSWORD elastic" | awk {' print $4 '}`
  fi  
  if [ -z ${PASSWD} ]; then
    echo "${red}[DEBUG]${reset} unable to find elastic users password"
    exit
  else
    echo "${green}[DEBUG]${reset} elastic user's password found ${PASSWD}"
  fi
} # end of grabpasswd function

# checking for the image and pull it
pullimage() {
  docker image inspect "${1}" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${green}[DEBUG]${reset} Pulling "${1}" image... might take a while"
    docker pull "${1}"
    if [ $? -ne 0  ]; then
      echo "${red}[DEBUG]${reset} Unable to pull "${1}". "
      exit
    fi
  else
    echo "${green}[DEBUG]${reset} "${1}" docker image already exists.."
  fi
} # end of pullimage function

# cleanup deployment
cleanup() {
  echo "${green}********** Cleaning up **********${reset}"
  docker stop es01 es02 es03 kibana metricbeat filebeat apm entsearch minio01 fleet es_mc_1 es_wait_until_ready_1 apm es_setup_1 es-setup-1 ldap >/dev/null 2>&1
  docker rm es01 es02 es03 kibana metricbeat filebeat apm entsearch minio01 fleet es_mc_1 es_wait_until_ready_1 apm es_setup_1 es-setup-1 ldap >/dev/null 2>&1
  docker network rm es_default >/dev/null 2>&1
  docker volume rm es_data01 >/dev/null 2>&1
  docker volume rm es_data02 >/dev/null 2>&1
  docker volume rm es_data03 >/dev/null 2>&1
  docker volume rm es_fleet >/dev/null 2>&1
  docker volume rm es_certs >/dev/null 2>&1
  docker volume rm es_kibanadata >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} Removed volumes and networks"

  rm -rf ${WORKDIR} >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} All cleanedup"

} # end of cleanup function

###############################################################################################################
# build stack

stack() {
  echo "${green}********** Deploying elasticsearch & kibana "${VERSION}" **********${reset}"

  # run checks to ensure you have all the prereqs
  checkmaxmapcount
  checkdocker
  checkcontainer

  # check to see if the directory exists should not since this is the start
  if [ -d ${WORKDIR} ]; then
    echo "${red}[DEBUG]${reset} Looks like ${WORKDIR} already exists.  Please run cleanup to delete the old deployment"
    help
	  exit
  fi # end of if to check if WORKDIR exist

  # create directorys and files
  mkdir -p ${WORKDIR}
  cd ${WORKDIR}
  mkdir temp
  echo ${VERSION} > VERSION

  # pull stack images
  pullimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
  pullimage "docker.elastic.co/kibana/kibana:${VERSION}"

  # generate temp elastic password
  PASSWD=`openssl rand -base64 29 | tr -d "=+/" | cut -c1-25`
  echo "${green}[DEBUG]${reset} Setting  password for elastic as ${PASSWD}"

  # Start build
  # if version is 8.0.0 or higher
  if [ $(checkversion $VERSION) -ge $(checkversion "8.0.0") ]; then
    
    # create elasticsearch.yml
    cat > elasticsearch.yml<<EOF
network.host: 0.0.0.0
xpack.security.authc.api_key.enabled: true
path.repo: "/temp"
EOF
    chown 1000 elasticsearch.yml >/dev/null 2>&1
    echo "${green}[DEBUG]${reset} elasticsearch.yml created"

    # create kibana.yml
    cat > kibana.yml<<EOF
server.host: "0.0.0.0"
server.shutdownTimeout: "5s"
EOF
    echo "${green}[DEBUG]${reset} kibana.yml created"

    # create .env file
    cat > .env<<EOF
ELASTIC_PASSWORD=${PASSWD}
KIBANA_PASSWORD=${PASSWD}
STACK_VERSION=${VERSION}
CLUSTER_NAME=lab
LICENSE=trial
ES_PORT=9200
KIBANA_PORT=5601
MEM_LIMIT=1073741824
COMPOSE_PROJECT_NAME=es
EOF
    echo "${green}[DEBUG]${reset} .env created"

    # start creating stack-compose.yml
    cat > stack-compose.yml<<EOF
version: "2.2"

services:
  setup:
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    volumes:
      - certs:/usr/share/elasticsearch/config/certs
      - ./temp:/temp
    user: "0"
    command: >
      bash -c '
        if [ x\${ELASTIC_PASSWORD} == x ]; then
          echo "Set the ELASTIC_PASSWORD environment variable in the .env file";
          exit 1;
        elif [ x\${KIBANA_PASSWORD} == x ]; then
          echo "Set the KIBANA_PASSWORD environment variable in the .env file";
          exit 1;
        fi;
        if [ ! -f certs/ca.zip ]; then
          echo "Creating CA";
          bin/elasticsearch-certutil ca --silent --pem -out config/certs/ca.zip;
          unzip config/certs/ca.zip -d config/certs; unzip config/certs/ca.zip -d /temp/certs;
        fi;
        if [ ! -f certs/certs.zip ]; then
          echo "Creating certs";
          echo -ne \
          "instances:\n"\
          "  - name: es01\n"\
          "    dns:\n"\
          "      - es01\n"\
          "      - localhost\n"\
          "    ip:\n"\
          "      - 127.0.0.1\n"\
          "  - name: es02\n"\
          "    dns:\n"\
          "      - es02\n"\
          "      - localhost\n"\
          "    ip:\n"\
          "      - 127.0.0.1\n"\
          "  - name: es03\n"\
          "    dns:\n"\
          "      - es03\n"\
          "      - localhost\n"\
          "    ip:\n"\
          "      - 127.0.0.1\n"\
          "  - name: kibana\n"\
          "    dns:\n"\
          "      - kibana\n"\
          "      - localhost\n"\
          "    ip:\n"\
          "      - 127.0.0.1\n"\
          "  - name: apm\n"\
          "    dns:\n"\
          "      - apm\n"\
          "      - localhost\n"\
          "    ip:\n"\
          "      - 127.0.0.1\n"\
          "  - name: entsearch\n"\
          "    dns:\n"\
          "      - entsearch\n"\
          "      - localhost\n"\
          "    ip:\n"\
          "      - 127.0.0.1\n"\
          "  - name: fleet\n"\
          "    dns:\n"\
          "      - fleet\n"\
          "      - localhost\n"\
          "    ip:\n"\
          "      - 127.0.0.1\n"\
          "  - name: minio01\n"\
          "    dns:\n"\
          "      - minio01\n"\
          "      - localhost\n"\
          "    ip:\n"\
          "      - 127.0.0.1\n"\
          > config/certs/instances.yml;
          bin/elasticsearch-certutil cert --silent --pem -out config/certs/certs.zip --in config/certs/instances.yml --ca-cert config/certs/ca/ca.crt --ca-key config/certs/ca/ca.key;
          unzip config/certs/certs.zip -d config/certs; unzip config/certs/certs.zip -d /temp/certs; chmod -R 777 /temp/certs;
        fi;
        echo "Setting file permissions"
        chown -R root:root config/certs;
        find . -type d -exec chmod 750 \{\} \;;
        find . -type f -exec chmod 640 \{\} \;;
        echo "Waiting for Elasticsearch availability";
        until curl -s --cacert config/certs/ca/ca.crt https://es01:9200 | grep -q "missing authentication credentials"; do sleep 30; done;
        echo "Setting kibana_system password";
        until curl -s -X POST --cacert config/certs/ca/ca.crt -u elastic:\${ELASTIC_PASSWORD} -H "Content-Type: application/json" https://es01:9200/_security/user/kibana_system/_password -d "{\"password\":\"\${KIBANA_PASSWORD}\"}" | grep -q "^{}"; do sleep 10; done;
        echo "All done!";
      '
    healthcheck:
      test: ["CMD-SHELL", "[ -f config/certs/es01/es01.crt ]"]
      interval: 1s
      timeout: 5s
      retries: 120

  es01:
    container_name: es01
    depends_on:
      setup:
        condition: service_healthy
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    labels:
      co.elastic.logs/module: elasticsearch
    volumes:
      - certs:/usr/share/elasticsearch/config/certs
      - data01:/usr/share/elasticsearch/data
      - ./temp:/temp
      - ./elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml
    ports:
      - \${ES_PORT}:9200
    environment:
      - node.name=es01
      - node.roles=master,data_content,data_hot,ingest,remote_cluster_client,ml,transform
      - node.attr.data=hot
      - node.attr.data2=hot
      - node.attr.zone=zone1
      - node.attr.zone2=zone1
      - cluster.name=\${CLUSTER_NAME}
      - cluster.initial_master_nodes=es01,es02,es03
      - discovery.seed_hosts=es02,es03
      - ELASTIC_PASSWORD=\${ELASTIC_PASSWORD}
      - bootstrap.memory_lock=true
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.http.ssl.key=certs/es01/es01.key
      - xpack.security.http.ssl.certificate=certs/es01/es01.crt
      - xpack.security.http.ssl.certificate_authorities=certs/ca/ca.crt
      - xpack.security.http.ssl.verification_mode=certificate
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.key=certs/es01/es01.key
      - xpack.security.transport.ssl.certificate=certs/es01/es01.crt
      - xpack.security.transport.ssl.certificate_authorities=certs/ca/ca.crt
      - xpack.security.transport.ssl.verification_mode=certificate
      - xpack.license.self_generated.type=\${LICENSE}
    mem_limit: \${MEM_LIMIT}
    ulimits:
      memlock:
        soft: -1
        hard: -1
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -s --cacert config/certs/ca/ca.crt https://localhost:9200 | grep -q 'missing authentication credentials'",
        ]
      interval: 10s
      timeout: 10s
      retries: 120

  es02:
    container_name: es02
    depends_on:
      - es01
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    labels:
      co.elastic.logs/module: elasticsearch
    volumes:
      - certs:/usr/share/elasticsearch/config/certs
      - data02:/usr/share/elasticsearch/data
      - ./temp:/temp
      - ./elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml
    environment:
      - node.name=es02
      - node.roles=master,data_content,data_hot,ingest,remote_cluster_client,ml,transform
      - node.attr.data=hot
      - node.attr.data2=warm
      - node.attr.zone=zone1
      - node.attr.zone2=zone2
      - cluster.name=\${CLUSTER_NAME}
      - cluster.initial_master_nodes=es01,es02,es03
      - discovery.seed_hosts=es01,es03
      - bootstrap.memory_lock=true
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.http.ssl.key=certs/es02/es02.key
      - xpack.security.http.ssl.certificate=certs/es02/es02.crt
      - xpack.security.http.ssl.certificate_authorities=certs/ca/ca.crt
      - xpack.security.http.ssl.verification_mode=certificate
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.key=certs/es02/es02.key
      - xpack.security.transport.ssl.certificate=certs/es02/es02.crt
      - xpack.security.transport.ssl.certificate_authorities=certs/ca/ca.crt
      - xpack.security.transport.ssl.verification_mode=certificate
      - xpack.license.self_generated.type=\${LICENSE}
    mem_limit: \${MEM_LIMIT}
    ulimits:
      memlock:
        soft: -1
        hard: -1
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -s --cacert config/certs/ca/ca.crt https://localhost:9200 | grep -q 'missing authentication credentials'",
        ]
      interval: 10s
      timeout: 10s
      retries: 120

  es03:
    container_name: es03
    depends_on:
      - es02
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    labels:
      co.elastic.logs/module: elasticsearch
    volumes:
      - certs:/usr/share/elasticsearch/config/certs
      - data03:/usr/share/elasticsearch/data
      - ./temp:/temp
      - ./elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml
    environment:
      - node.name=es03
      - node.roles=master,data_frozen,ingest,remote_cluster_client,ml,transform
      - xpack.searchable.snapshot.shared_cache.size=20%
      - node.attr.data=warm
      - node.attr.data2=cold
      - node.attr.zone=zone2
      - node.attr.zone2=zone3
      - cluster.name=\${CLUSTER_NAME}
      - cluster.initial_master_nodes=es01,es02,es03
      - discovery.seed_hosts=es01,es02
      - bootstrap.memory_lock=true
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.http.ssl.key=certs/es03/es03.key
      - xpack.security.http.ssl.certificate=certs/es03/es03.crt
      - xpack.security.http.ssl.certificate_authorities=certs/ca/ca.crt
      - xpack.security.http.ssl.verification_mode=certificate
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.key=certs/es03/es03.key
      - xpack.security.transport.ssl.certificate=certs/es03/es03.crt
      - xpack.security.transport.ssl.certificate_authorities=certs/ca/ca.crt
      - xpack.security.transport.ssl.verification_mode=certificate
      - xpack.license.self_generated.type=\${LICENSE}
    mem_limit: \${MEM_LIMIT}
    ulimits:
      memlock:
        soft: -1
        hard: -1
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -s --cacert config/certs/ca/ca.crt https://localhost:9200 | grep -q 'missing authentication credentials'",
        ]
      interval: 10s
      timeout: 10s
      retries: 120

  kibana:
    container_name: kibana
    depends_on:
      es01:
        condition: service_healthy
      es02:
        condition: service_healthy
      es03:
        condition: service_healthy
    image: docker.elastic.co/kibana/kibana:${VERSION}
    labels:
      co.elastic.logs/module: kibana
    volumes:
      - certs:/usr/share/kibana/config/certs
      - kibanadata:/usr/share/kibana/data
      - ./temp:/temp
      - ./kibana.yml:/usr/share/kibana/config/kibana.yml
    ports:
      - \${KIBANA_PORT}:5601
    environment:
      - SERVERNAME=kibana
      - ELASTICSEARCH_HOSTS=https://es01:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=\${KIBANA_PASSWORD}
      - ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES=config/certs/ca/ca.crt
      - SERVER_SSL_ENABLED=true
      - SERVER_SSL_CERTIFICATE=config/certs/kibana/kibana.crt
      - SERVER_SSL_KEY=config/certs/kibana/kibana.key
    mem_limit: \${MEM_LIMIT}
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -s --cacert config/certs/ca/ca.crt -I https://localhost:5601 | grep -q 'HTTP/1.1 302 Found'",
        ]
      interval: 10s
      timeout: 10s
      retries: 120

volumes:
  certs:
    driver: local
  data01:
    driver: local
  data02:
    driver: local
  data03:
    driver: local
  kibanadata:
    driver: local
EOF
    echo "${green}[DEBUG]${reset} stack-compose.yml created"

    # start cluster
    echo "${green}[DEBUG]${reset} Starting our deployment"
    docker-compose -f stack-compose.yml up -d

    # copy out ca.crt to ${WORKDIR}
    cp ${WORKDIR}/temp/certs/ca/ca.crt ${WORKDIR}/
    chmod 644 ${WORKDIR}/ca.crt
    echo "${green}[DEBUG]${reset} Copied ca.crt to ${WORKDIR}"
    
    # Copy the password to notes
    cat ${WORKDIR}/.env | grep PASSWORD > ${WORKDIR}/notes

    # generate kibana encryption key
    ENCRYPTION_KEY=`openssl rand -base64 40 | tr -d "=+/" | cut -c1-32`

    # update kibana.yml with encryption keys
    cat >> kibana.yml<<EOF
xpack.security.encryptionKey: "${ENCRYPTION_KEY}"
xpack.reporting.encryptionKey: "${ENCRYPTION_KEY}"
xpack.encryptedSavedObjects.encryptionKey: "${ENCRYPTION_KEY}"
xpack.reporting.kibanaServer.hostname: "localhost"
EOF
    echo "${green}[DEBUG]${reset} Generated encryption keys for kibana"
    
    # restarting kibana
    docker restart kibana >/dev/null 2>&1
    echo "${green}[DEBUG]${reset} Restarted kibana to pick encryption keys"

    # end of build for 8.0.0+
  
  elif [ $(checkversion $VERSION) -lt $(checkversion "8.0.0") ]; then

    # start build for 8.0.0-

    # create elasticsearch.yml
    cat > elasticsearch.yml<<EOF
network.host: 0.0.0.0
xpack.security.authc.api_key.enabled: true
path.repo: "/temp"
EOF
    chown 1000 elasticsearch.yml >/dev/null 2>&1
    echo "${green}[DEBUG]${reset} Created elasticsearch.yml"

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

  - name: fleet
    dns:
      - fleet
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
        yum install -y -q -e 0 unzip >/dev/null 2>&1;
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
  "

    if [ $(checkversion $VERSION) -ge $(checkversion "7.2.0") ]; then
      echo "${createcertscurrent}" > create-certs.yml
    else
      echo "${createcerts6}" > create-certs.yml
    fi
    echo "${green}[DEBUG]${reset} Created create-certs.yml for ${VERSION}"

    # create certificates
    echo "${green}[DEBUG]${reset} Create certificates"
    docker-compose -f create-certs.yml run --rm create_certs

    # create stack-compose.yml
    stackcomposecurrentp1="version: '2.2'

services:
  es01:
    container_name: es01
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es01
      - node.roles=master,data_content,data_hot,ingest,remote_cluster_client,ml,transform
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
      - node.roles=master,data_content,data_hot,ingest,remote_cluster_client,ml,transform
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
      - node.roles=master,data_frozen,ingest,remote_cluster_client,ml,transform
      - xpack.searchable.snapshot.shared_cache.size=1GB
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
  "

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
  "
    if [ $(checkversion $VERSION) -ge $(checkversion "7.12.0") ]; then
      echo "${stackcomposecurrentp1}" > stack-compose.yml
    elif [ $(checkversion $VERSION) -ge $(checkversion "7.2.0") ]; then
      echo "${stackcomposecurrent}" > stack-compose.yml
    elif [ $(checkversion $VERSION) -lt $(checkversion "7.2.0") ] && [ $(checkversion $VERSION) -ge $(checkversion "7.0.0") ]; then
      echo "${stackcompose71}" > stack-compose.yml
    elif [ $(checkversion $VERSION) -lt $(checkversion "7.0.0") ]; then
      echo "${stackcompose6}" > stack-compose.yml
      if [ $(checkversion $VERSION) -le $(checkversion "6.5.0") ]; then
        if [ "`uname -s`" != "Darwin" ]; then
          sed -i 's/ELASTICSEARCH_HOSTS.*/ELASTICSEARCH_URL=https:\/\/es01:9200/g' stack-compose.yml
        else
          sed -i '' -E 's/ELASTICSEARCH_HOST.*/ELASTICSEARCH_URL=https:\/\/es01:9200/g' stack-compose.yml
        fi
      fi
    fi
    echo "${green}[DEBUG]${reset} Created stack-compose.yml for ${VERSION}"


    # start cluster
    echo "${green}[DEBUG]${reset} Starting our deployment"
    docker-compose -f stack-compose.yml up -d

    # copy the certificate authority into the homedir for the project
    if [ $(checkversion $VERSION) -ge $(checkversion "7.2.0") ]; then
      docker exec es01 /bin/bash -c "cp /usr/share/elasticsearch/config/certificates/ca/ca.* /temp/"
      mv ${WORKDIR}/temp/ca.* ${WORKDIR}/
    else
      cp ${WORKDIR}/certs/ca/ca.* ${WORKDIR}/
    fi
    
    echo "${green}[DEBUG]${reset} Copied ca.crt into ${WORKDIR}"
    
    # wait for cluster to be healthy
    checkhealth

    # setup passwords
    echo "${green}[DEBUG]${reset} Setting passwords and storing it in ${PWD}/notes"
    if [ $(checkversion $VERSION) -ge $(checkversion "7.6.0") ]; then
      docker exec es01 /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch \
--url https://localhost:9200" | tee -a notes
    elif [ $(checkversion $VERSION) -lt $(checkversion "7.6.0") ] && [ $(checkversion $VERSION) -ge $(checkversion "7.0.0") ]; then
      docker exec es01 /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch \
-Expack.security.http.ssl.certificate=certificates/es01/es01.crt \
-Expack.security.http.ssl.certificate_authorities=certificates/ca/ca.crt \
-Expack.security.http.ssl.key=certificates/es01/es01.key \
--url https://localhost:9200" | tee -a notes
    elif [ $(checkversion $VERSION) -lt $(checkversion "7.0.0") ]; then
      docker exec es01 /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch \
-Expack.security.http.ssl.certificate_authorities=certificates/ca/ca.crt \
--url https://localhost:9200" | tee -a notes
    fi
     
    # grab the new elastic password
    grabpasswd

    # generate kibana encryption key
    ENCRYPTION_KEY=`openssl rand -base64 40 | tr -d "=+/" | cut -c1-32`

    # create kibana.yml
    if [ $(checkversion $VERSION) -lt $(checkversion "7.7.0") ]; then
      cat > kibana.yml<<EOF
elasticsearch.username: "elastic"
elasticsearch.password: "${PASSWD}"
xpack.security.encryptionKey: "${ENCRYPTION_KEY}"
xpack.reporting.encryptionKey: "${ENCRYPTION_KEY}"
EOF
    else
      cat > kibana.yml<<EOF
elasticsearch.username: "elastic"
elasticsearch.password: "${PASSWD}"
xpack.security.encryptionKey: "${ENCRYPTION_KEY}"
xpack.reporting.encryptionKey: "${ENCRYPTION_KEY}"
xpack.encryptedSavedObjects.encryptionKey: "${ENCRYPTION_KEY}"
EOF
    fi

    echo "${green}[DEBUG]${reset} kibana.yml re-generated with new password and encryption keys"

    # restart kibana
    docker restart kibana >/dev/null 2>&1
    echo "${green}[DEBUG]${reset} Restarted kibana to pick up the new elastic password"

  fi   

  echo "${green}[DEBUG]${reset} Complete! - stack deployed. ${VERSION} elastic password: ${PASSWD}"
  echo ""
  
  checkhealth

  # new add local fs repository for /temp 
  curl -k -u elastic:${PASSWD} -XPUT "https://localhost:9200/_snapshot/local_temp" -H 'Content-Type: application/json' -d'
{
  "type" : "fs",
  "settings" : {
    "location": "/temp"
  }
}' >/dev/null 2>&1
} # build stack end


###############################################################################################################

monitor() {
  # check to make sure that ES is 6.6 or greater
  if [ $(checkversion $VERSION) -lt $(checkversion "6.5.0") ]; then
    echo "${red}[DEBUG]${reset} metricbeats collections started with 6.5+.  Please use legacy collections method"
    help
    exit
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
    exit
  fi

  # check to see if version match
  OLDVERSION="`cat VERSION`"
  if [ $(checkversion $VERSION) -gt $(checkversion $OLDVERSION) ]; then
    echo "${red}[DEBUG]${reset} Version needs to be equal or lower than stack version ${OLDVERSION}"
    exit
  fi

  # grab the elastic password
  grabpasswd
    
  # check health
  checkhealth

  # add MB_CERTS_DIR & FB_CERTS to .env
  cat >> .env<<EOF
MB_CERTS_DIR=/usr/share/metricbeat/certificates
FB_CERTS_DIR=/usr/share/filebeat/certificates
EOF

  echo "${green}[DEBUG]${reset} Added MB_CERTS_DIR & FB_CERTS_DIR to .env"

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

  if [ $(checkversion $VERSION) -ge $(checkversion "8.0.0") ]; then
    
    # set password for remote_monitoring_user
    RMUPASSWD=`docker exec es01 bin/elasticsearch-reset-password -u remote_monitoring_user -a -s -b` 
    echo "REMOTE_MONITORING_USER=${RMUPASSWD}" >> ${WORKDIR}/notes

    # create metricbeat_monitoring role
    curl -s -k -u "elastic:${PASSWD}" -XPUT "https://localhost:9200/_security/role/metricbeat_monitoring" -H 'Content-Type: application/json' -d'
{
  "cluster": [
    "monitor"
  ],
  "indices": [
    {
      "names": [
        ".monitoring-beats-*"
      ],
      "privileges": [
        "create_index",
        "create_doc"
      ]
    }
  ]
}' >/dev/null 2>&1
    echo "${green}[DEBUG]${reset} Created metricbeat_monitoring role"

    # create metricbeat_monitoring_user
    curl -s -k -u "elastic:${PASSWD}" -XPUT "https://localhost:9200/_security/user/metricbeat_monitoring_user" -H 'Content-Type: application/json' -d'
{
  "password": "test12345",
  "roles": [
    "metricbeat_monitoring",
    "monitoring_user",
    "kibana_admin",
    "remote_monitoring_collector",
    "remote_monitoring_agent"
  ]
}' >/dev/null 2>&1
    echo "${green}[DEBUG]${reset} Created metricbeat_monitoring_user user"

    MMUPASSWD="test12345"
    echo "METRICBEAT_MONITORING_USER=${MMUPASSWD}" >> ${WORKDIR}/notes

    # create filebeat_writer role
    curl -s -k -u "elastic:${PASSWD}" -XPUT "https://localhost:9200/_security/role/filebeat_writer" -H 'Content-Type: application/json' -d'
{
  "cluster": [
    "monitor",
    "read_pipeline",
    "read_ilm",
    "manage"
  ],
  "indices": [
    {
      "names": [
        "filebeat-*"
      ],
      "privileges": [
        "create_doc",
        "view_index_metadata",
        "create_index"
      ]
    },
    {
      "names": [
        "filebeat-*",
        ".ds-filebeat-*"
      ],
      "privileges": [
        "manage",
        "manage_follow_index",
        "all"
      ]
    }
  ]
}' >/dev/null 2>&1
    echo "${green}[DEBUG]${reset} Created filebeat_writer role"

    # create filebeat_monitoring_user
    curl -s -k -u "elastic:${PASSWD}" -XPUT "https://localhost:9200/_security/user/filebeat_writer_user" -H 'Content-Type: application/json' -d'
{
  "password": "test12345",
  "roles": [
    "filebeat_writer"
  ]
}' >/dev/null 2>&1
    echo "${green}[DEBUG]${reset} Created filebeat_writer_user user"

    FWUPASSWD="test12345"
    echo "FILEBEAT_WRITER_USER=${FWUPASSWD}" >> ${WORKDIR}/notes

  fi 
  
  # metricbeat!!
  # Create templates
  common8="# common
http.enabled: true
http.port: 5066
http.host: 0.0.0.0

processors:
  - add_cloud_metadata: ~
  - add_docker_metadata: ~

monitoring.enabled: false

output.elasticsearch:
  hosts: [\"https://es01:9200\", \"https://es02:9200\", \"https://es03:9200\"]
  username: \"metricbeat_monitoring_user\"
  password: "\"${MMUPASSWD}\""
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
  username: \"remote_monitoring_user\"
  password: "\"${RMUPASSWD}\""
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/metricbeat/certificates/ca/ca.crt\"]
  "

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
  
  es8="# Module: elasticsearch
- module: elasticsearch
  xpack.enabled: true
  period: 10s
  hosts: [\"https://es01:9200\", \"https://es02:9200\", \"https://es03:9200\"]
  username: \"remote_monitoring_user\"
  password: "\"${RMUPASSWD}\""
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

  # create metricbeat.yml
  # common section
  if [ ${MAJOR} = "8" ]; then
    echo "${common8}" > metricbeat.yml
  elif [ ${MAJOR} = "7" ]; then
    echo "${common7}" > metricbeat.yml
  elif [ ${MAJOR} = "6" ]; then
    echo "${common6}" > metricbeat.yml
  fi

  # beats section
  if [ $(checkversion $VERSION) -ge $(checkversion "7.3.0") ]; then
    echo "${beats}" >> metricbeat.yml
  fi

  # es section
  if [ $(checkversion $VERSION) -ge $(checkversion "8.0.0") ]; then
    echo "${es8}" >> metricbeat.yml
  elif [ $(checkversion $VERSION) -ge $(checkversion "7.9.0") ] && [ $(checkversion $VERSION) -lt $(checkversion "8.0.0") ]; then
    echo "${escurrent}" >> metricbeat.yml
  elif [ $(checkversion $VERSION) -ge $(checkversion "7.5.0") ] && [ $(checkversion $VERSION) -lt $(checkversion "7.9.0") ]; then
    echo "${es78}" >> metricbeat.yml
  elif [ $(checkversion $VERSION) -ge $(checkversion "7.2.0") ] && [ $(checkversion $VERSION) -lt $(checkversion "7.5.0") ]; then
    echo "${es74}" >> metricbeat.yml
  else
    echo "${es74}" >> metricbeat.yml
    if [ "`uname -s`" != "Darwin" ]; then
      sed -i 's/full/none/g' metricbeat.yml
    else
      sed -i '' -E 's/full/none/g' metricbeat.yml
    fi
  fi

  chmod go-w metricbeat.yml >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} Created metricbeat.yml"


  # filebeatbeat!!
  
fb8="#
http.enabled: true
http.port: 5066
http.host: 0.0.0.0
monitoring.enabled: false

filebeat.autodiscover:
  providers:
    - type: docker
      hints.enabled: true

processors:
  - add_cloud_metadata: ~
  - add_docker_metadata: ~

output.elasticsearch:
  hosts: [\"https://es01:9200\", \"https://es02:9200\", \"https://es03:9200\"]
  username: \"filebeat_writer_user\"
  password: \"${FWUPASSWD}\"
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/filebeat/certificates/ca/ca.crt\"]
"

fb7="#
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
  hosts: [\"https://es01:9200\", \"https://es02:9200\", \"https://es03:9200\"]
  username: \"elastic\"
  password: \"${PASSWD}\"
  ssl.enabled: true
  ssl.verification_mode: full
  ssl.certificate_authorities: [\"/usr/share/filebeat/certificates/ca/ca.crt\"]
"
  
  # create filebeat.yml
  if [ $(checkversion $VERSION) -ge $(checkversion "8.0.0") ]; then
    echo "${fb8}" > filebeat.yml
  elif [ $(checkversion $VERSION) -ge $(checkversion "7.2.0") ] && [ $(checkversion $VERSION) -lt $(checkversion "8.0.0") ]; then
    echo "${fb7}" > filebeat.yml
  else
    echo "${fb7}" > filebeat.yml
    if [ "`uname -s`" != "Darwin" ]; then
      sed -i 's/full/none/g' filebeat.yml
    else
      sed -i '' -E 's/full/none/g' filebeat.yml
    fi
  fi

  echo "${green}[DEBUG]${reset} Created filebeat.yml"

  if [ $(checkversion $VERSION) -ge $(checkversion "8.0.0") ]; then
    STRINGMB="command: metricbeat -environment container --strict.perms=false"
    STRINGFB="command: filebeat -environment container --strict.perms=false"
  elif [ $(checkversion $VERSION) -ge $(checkversion "7.7.0") ] && [ $(checkversion $VERSION) -lt $(checkversion "8.0.0") ]; then
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
    labels:
      co.elastic.logs/module: beats
    volumes: ['./metricbeat.yml:/usr/share/metricbeat/metricbeat.yml', 'certs:\$MB_CERTS_DIR', './temp:/temp', '/var/run/docker.sock:/var/run/docker.sock:ro']
    restart: on-failure
  filebeat:
    container_name: filebeat
    user: root
    ${STRINGFB}
    image: docker.elastic.co/beats/filebeat:${VERSION}
    labels:
      co.elastic.logs/module: beats
    volumes: ['./filebeat.yml:/usr/share/filebeat/filebeat.yml', 'certs:\$FB_CERTS_DIR', './temp:/temp', '/var/lib/docker/containers:/var/lib/docker/containers:ro', '/var/run/docker.sock:/var/run/docker.sock:ro']
    restart: on-failure

volumes: {"certs"}
EOF
  
  if [ $(checkversion $VERSION) -lt $(checkversion "7.2.0") ]; then
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

  # TODO: need section for add monitoring for enterprise search if metricbeat.yml exists
  ##
  ##
  # add monitoring if monitoring is enabled and if enterprise search is 7.16.0+
  if [ $(checkversion $VERSION) -ge $(checkversion "7.16.0") ]; then
    if [ -f "${WORKDIR}/entsearch-compose.yml" ]; then
      echo "${green}[DEBUG]${reset} enterprise search found and the stack is 7.16.0+ - enabling enterprisesearch monitoring"
      cat >> ${WORKDIR}/metricbeat.yml<<EOF
metricbeat.modules:
- module: enterprisesearch
  metricsets: ["health", "stats"]
  enabled: true
  period: 10s
  hosts: ["http://entsearch:3002"]
  username: "elastic"
  password: "${PASSWD}"
EOF

    fi
  fi

  # start service
  echo "${green}[DEBUG]${reset} Starting monitoring....."
  docker-compose -f monitor-compose.yml up -d >/dev/null 2>&1


} # End of monitor function


###############################################################################################################

snapshot() {
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
    exit
  fi

  # check to see if version match
  OLDVERSION="`cat VERSION`"
  if [ $(checkversion $VERSION) -gt $(checkversion $OLDVERSION) ]; then
    echo "${red}[DEBUG]${reset} Version needs to be equal or lower than stack version ${OLDVERSION}"
    exit
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
    if [ $(checkversion $VERSION) -ge $(checkversion "7.0.0") ]; then
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
  if [ $(checkversion $VERSION) -ge $(checkversion "7.0.0") ]; then
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
    
    if [ $(checkversion $VERSION) -ge $(checkversion "7.4.0") ]; then
      curl -k -u elastic:${PASSWD} -XPUT "https://localhost:9200/_slm/policy/minio-snapshot-policy" -H 'Content-Type: application/json' -d'{  "schedule": "0 */30 * * * ?",   "name": "<minio-snapshot-{now/d}>",   "repository": "minio01",   "config": {     "partial": true  },  "retention": {     "expire_after": "5d",     "min_count": 1,     "max_count": 20   }}' >/dev/null 2>&1
      echo "${green}[DEBUG]${reset} Added minio-snapshot-policy"
      sleep 3
      curl -k -u elastic:${PASSWD} -XPUT "https://localhost:9200/_slm/policy/minio-snapshot-policy/_execute" >/dev/null 2>&1
      echo "${green}[DEBUG]${reset} Executed minio-snapshot-policy"
    fi
  elif [ $(checkversion $VERSION) -lt $(checkversion "7.0.0") ]; then
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

}  # End of snapshot function


###############################################################################################################

fleet() {
  # check to make sure that ES is 7.7 or greater
  if [ $(checkversion $VERSION) -lt $(checkversion "7.10.0") ]; then
    echo "${red}[DEBUG]${reset} FLEET started with 7.10+."
    help
    return
  fi

  # check to see if ${WORKDIR} exits
  if [ ! -d ${WORKDIR} ]; then
    echo "${red}[DEBUG]${reset} Deployment does not exist.  Starting deployment first"
    stack ${VERSION}
    echo "${green}********** Deploying FLEET **********${reset}"
  else
    cd ${WORKDIR}
    echo "${green}********** Deploying FLEET **********${reset}"
  fi

  # check to see if fleet-compose.yml already exists.
  if [ -f "fleet-compose.yml" ]; then
    echo "${red}[DEBUG]${reset} fleet-compose.yml already exists. Exiting."
    exit
  fi

  # check to see if version match
  OLDVERSION="`cat VERSION`"
  if [ $(checkversion $VERSION) -gt $(checkversion $OLDVERSION) ]; then
    echo "${red}[DEBUG]${reset} Version needs to be equal or lower than stack version ${OLDVERSION}"
    exit
  fi

  # grab the elastic password
  grabpasswd

  # check health before continuing
  checkhealth

  # pull image
  pullimage "docker.elastic.co/beats/elastic-agent:${VERSION}"

  # get IP
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    IP=`ip route get 8.8.8.8 | head -1 | cut -d' ' -f7`
    echo "${green}[DEBUG]${reset} OS: LINUX   IP found: ${IP}"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    INTERFACE=`netstat -rn | grep UGScg | awk '{ print $NF }'| tail -n1`
    IP=`ifconfig ${INTERFACE} | grep inet | awk '{ print $2 }'`
    echo "${green}[DEBUG]${reset} OS: macOS   IP found: ${IP}"
  else
    IP="NEED-2-UPDATE"
    echo "${red}[DEBUG]${reset} OS: UNKNONW(script only works with linux or macOS)   IP found: ${IP}"
  fi

  # add to .env
  cat >> .env<<EOF
FLEET_CERTS_DIR=/usr/share/elastic-agent/certificates
EOF

  # add to elasticsearch.yml if it doesnt exist
  if [ `grep -c "xpack.security.authc.api_key.enabled" ${WORKDIR}/elasticsearch.yml` = 0 ]; then
    cat >> elasticsearch.yml<<EOF
xpack.security.authc.api_key.enabled: true
EOF
    # restart elasticsearch
    for instance in es01 es02 es03
    do
      docker restart ${instance}>/dev/null 2>&1
      sleep 10
      echo "${green}[DEBUG]${reset} Restarting ${instance} for FLEET"
    done
    
    checkhealth

  fi

  # bootstrap fleet on ES & KB
  echo "${green}[DEBUG]${reset} Setting up kibana for fleet"
#  flag="false"
#  while [ "${flag}" != "true" ]
#  do
#    flag=`curl -k -s -u "elastic:${PASSWD}" -s -XPOST https://localhost:5601/api/fleet/setup --header 'kbn-xsrf: true' | jq -r '.isInitialized' 2>/dev/null`
#    sleep 5
#    echo "${green}[DEBUG]${reset} Fleet setup for kibana started. Will check status every 5 seconds until finished..."
#  done
  echo ""
  until [ $(curl -k -s -u "elastic:${PASSWD}" -s -XPOST https://localhost:5601/api/fleet/setup --header 'kbn-xsrf: true' | jq -r '.isInitialized' 2>/dev/null) ]; do
    sleep 2
  done &
  spinner $! "${blue}[DEBUG]${reset} Waiting for fleet setup to complete.  If this runs for longer than ~ 1 minute something is wrong"
  echo ""
  
  # create fleet.yml
  if [ ! -f ${WORKDIR}/fleet.yml ]; then
    # touch ${WORKDIR}/fleet.yml
    cat > ${WORKDIR}/fleet.yml <<EOF
agent.monitoring:
enabled: true 
  logs: true 
  metrics: true 
  http:
      enabled: true 
      host: 0.0.0.0 
      port: 6791 
EOF
  fi

  # Setting Fleet URL
  echo "${green}[DEBUG]${reset} Setting Fleet URL as https://'${IP}':8220"
  curl -k -u "elastic:${PASSWD}" -XPUT "https://localhost:5601/api/fleet/settings" \
  --header 'kbn-xsrf: true' \
  --header 'Content-Type: application/json' \
  -d '{"fleet_server_hosts":["https://'${IP}':8220"]}' >/dev/null 2>&1

  if [ $(checkversion $VERSION) -lt $(checkversion "8.1.0") ]; then
    
    # Get policy_id
    POLICYID=`curl -k -s -u elastic:${PASSWD} -XGET https://localhost:5601/api/fleet/agent_policies | jq -r '.items[] | select (.name | contains("Server policy")).id'`
    echo "${green}[DEBUG]${reset} Fleet Server Policy ID: ${POLICYID}"

    # Get enrollment token
    ENROLLTOKEN=`curl -k -s -u elastic:${PASSWD} -XGET "https://localhost:5601/api/fleet/enrollment-api-keys" | jq -r '.list[] | select (.policy_id |contains("'${POLICYID}'")).api_key'`
    echo "${green}[DEBUG]${reset} Fleet Server Enrollment API KEY: ${ENROLLTOKEN}"

    # Create service token
    SERVICETOKEN=`curl -k -u "elastic:${PASSWD}" -s -X POST https://localhost:5601/api/fleet/service-tokens --header 'kbn-xsrf: true' | jq -r .value`
    echo "${green}[DEBUG]${reset} Generated SERVICE TOKEN for fleet server: ${SERVICETOKEN}"

    # generate fleet-compose.yml
    cat > fleet-compose.yml<<EOF
version: '2.2'

services:
  fleet:
    container_name: fleet
    user: root
    image: docker.elastic.co/beats/elastic-agent:${VERSION}
    environment:
      - FLEET_SERVER_ENABLE=true
      - FLEET_URL=https://fleet:8220
      - FLEET_ENROLLMENT_TOKEN=${ENROLLTOKEN}
      - FLEET_CA=/usr/share/elastic-agent/certificates/ca/ca.crt
      - FLEET_SERVER_ELASTICSEARCH_HOST=https://es01:9200
      - FLEET_SERVER_ELASTICSEARCH_CA=/usr/share/elastic-agent/certificates/ca/ca.crt
      - FLEET_SERVER_CERT=/usr/share/elastic-agent/certificates/fleet/fleet.crt
      - FLEET_SERVER_CERT_KEY=/usr/share/elastic-agent/certificates/fleet/fleet.key
      - FLEET_SERVER_SERVICE_TOKEN=${SERVICETOKEN}
      - CERTIFICATE_AUTHORITIES=/usr/share/elastic-agent/certificates/ca/ca.crt
    ports:
      - 8220:8220
      - 6791:6791
      - 8200:8200
    restart: on-failure
    volumes: ['certs:\$FLEET_CERTS_DIR', './temp:/temp', './fleet.yml:/usr/share/elastic-agent/fleet.yml']

volumes: {"certs"}
EOF

    echo "${green}[DEBUG]${reset} Created fleet-compose.yml"

#    # Setting Fleet URL
#    echo "${green}[DEBUG]${reset} Setting Fleet URL"
#    curl -k -u "elastic:${PASSWD}" -XPUT "https://localhost:5601/api/fleet/settings" \
#    --header 'kbn-xsrf: true' \
#    --header 'Content-Type: application/json' \
#    -d '{"fleet_server_hosts":["https://'${IP}':8220"]}' >/dev/null 2>&1
#
#    sleep 5
    
    ## ssl ca
    if [ -f ${WORKDIR}/ca.temp ]; then
      rm -rf ${WORKDIR}/ca.temp
    fi
    while read line
    do
      echo "    ${line}" >> ${WORKDIR}/ca.temp
    done < ${WORKDIR}/ca.crt
    truncate -s -1 ${WORKDIR}/ca.temp
    CA=$(jq -R -s '.' < ${WORKDIR}/ca.temp | tr -d '"')
    rm -rf ${WORKDIR}/ca.temp

    if [ $(checkversion $VERSION) -lt $(checkversion "8.0.0") ]; then
      generate_post_data()
        {
          cat <<EOF
{
  "hosts":["https://${IP}:9200"],
  "config_yaml":"ssl:\n  verification_mode: none\n  certificate_authorities:\n  - |\n${CA}"
}
EOF
        }

      curl -k -u "elastic:${PASSWD}" -XPUT "https://localhost:5601/api/fleet/outputs/fleet-default-output" \
      --header 'kbn-xsrf: true' \
      --header 'Content-Type: application/json' \
      -d "$(generate_post_data)" >/dev/null 2>&1

      sleep 5
    else

      generate_post_data()
      {
        cat <<EOF
{
  "name": "default",
  "type": "elasticsearch",
  "hosts": ["https://${IP}:9200"],
  "is_default": true,
  "is_default_monitoring": true,
  "ca_trusted_fingerprint": "${FINGERPRINT}",
  "config_yaml": "ssl:\n  verification_mode: none\n  certificate_authorities:\n  - |\n${CA}"
}
EOF
      }

      curl -k -u "elastic:${PASSWD}" -XPUT "https://localhost:5601/api/fleet/outputs/fleet-default-output" \
      --header 'kbn-xsrf: true' \
      --header 'Content-Type: application/json' \
      -d "$(generate_post_data)" >/dev/null 2>&1

      sleep 5

    fi

  elif [ $(checkversion $VERSION) -ge $(checkversion "8.1.0") ]; then
  
    # Create Fleet server policy
    echo "${green}[DEBUG]${reset} Creating Fleet Server Policy"
    curl -k -u "elastic:${PASSWD}" "https://localhost:5601/api/fleet/agent_policies?sys_monitoring=true" \
    --header 'kbn-xsrf: true' \
    --header 'Content-Type: application/json' \
    -d '{"id":"fleet-server-policy","name":"Fleet Server policy","description":"","namespace":"default","monitoring_enabled":["logs","metrics"],"has_fleet_server":true}' >/dev/null 2>&1

    sleep 5
    
#    # Setting Fleet URL
#    echo "${green}[DEBUG]${reset} Setting Fleet URL"
#    curl -k -u "elastic:${PASSWD}" -XPUT "https://localhost:5601/api/fleet/settings" \
#    --header 'kbn-xsrf: true' \
#    --header 'Content-Type: application/json' \
#    -d '{"fleet_server_hosts":["https://'${IP}':8220"]}' >/dev/null 2>&1
#
#    sleep 5

    # setting Elasticsearch URL and SSL certificate and fingerprint
    echo "${green}[DEBUG]${reset} Setting Elasticsearch URL & Fingerprint & SSL CA"
    
    ## fingerprint
    FINGERPRINT=`openssl x509 -fingerprint -sha256 -noout -in ${WORKDIR}/ca.crt | awk -F"=" {' print $2 '} | sed s/://g`
    
    ## ssl ca
    if [ -f ${WORKDIR}/ca.temp ]; then
      rm -rf ${WORKDIR}/ca.temp
    fi
    while read line
    do
      echo "    ${line}" >> ${WORKDIR}/ca.temp
    done < ${WORKDIR}/ca.crt
    truncate -s -1 ${WORKDIR}/ca.temp
    CA=$(jq -R -s '.' < ${WORKDIR}/ca.temp | tr -d '"')
    rm -rf ${WORKDIR}/ca.temp

    generate_post_data()
    {
      cat <<EOF
{
  "name": "default",
  "type": "elasticsearch",
  "hosts": ["https://${IP}:9200"],
  "is_default": true,
  "is_default_monitoring": true,
  "ca_trusted_fingerprint": "${FINGERPRINT}",
  "config_yaml": "ssl:\n  verification_mode: none\n  certificate_authorities:\n  - |\n${CA}"
}
EOF
    }

    curl -k -u "elastic:${PASSWD}" -XPUT "https://localhost:5601/api/fleet/outputs/fleet-default-output" \
    --header 'kbn-xsrf: true' \
    --header 'Content-Type: application/json' \
    -d "$(generate_post_data)" >/dev/null 2>&1

    sleep 5

    # Create service token
    SERVICETOKEN=`curl -k -u "elastic:${PASSWD}" -s -X POST https://localhost:5601/api/fleet/service-tokens --header 'kbn-xsrf: true' | jq -r .value`
    echo "${green}[DEBUG]${reset} Generated SERVICE TOKEN for fleet server: ${SERVICETOKEN}"

    # generate fleet-compose.yml
    cat > fleet-compose.yml<<EOF
version: '2.2'

services:
  fleet:
    container_name: fleet
    user: root
    image: docker.elastic.co/beats/elastic-agent:${VERSION}
    environment:
      - FLEET_SERVER_ENABLE=true
      - FLEET_URL=https://fleet:8220
      - FLEET_CA=/usr/share/elastic-agent/certificates/ca/ca.crt
      - FLEET_SERVER_ELASTICSEARCH_HOST=https://es01:9200
      - FLEET_SERVER_ELASTICSEARCH_CA=/usr/share/elastic-agent/certificates/ca/ca.crt
      - FLEET_SERVER_CERT=/usr/share/elastic-agent/certificates/fleet/fleet.crt
      - FLEET_SERVER_CERT_KEY=/usr/share/elastic-agent/certificates/fleet/fleet.key
      - FLEET_SERVER_SERVICE_TOKEN=${SERVICETOKEN}
      - FLEET_SERVER_POLICY=fleet-server-policy
      - CERTIFICATE_AUTHORITIES=/usr/share/elastic-agent/certificates/ca/ca.crt
    ports:
      - 8220:8220
      - 6791:6791
    restart: on-failure
    volumes: ['certs:\$FLEET_CERTS_DIR', './temp:/temp', './fleet.yml:/usr/share/elastic-agent/fleet.yml']

volumes: {"certs"}
EOF

    echo "${green}[DEBUG]${reset} Created fleet-compose.yml"

  fi

  docker-compose -f fleet-compose.yml up -d >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} Started FLEET SERVER. - Please give it about a minute for things to settle before you go into the FLEET app."

  echo ""
  echo "${red}[DEBUG]${reset} Not sure if its my script or a bug but even when the Fleet server is registered correctly and healthy and you send the kibana API call to set the default fleet output"
  echo "${red}[DEBUG]${reset} It updates the Fleet Settings in kibana but does not update the Fleet server's state.yml in 7.x" 
  echo "${red}[DEBUG]${reset} Please browse to Fleet Settings and add something like \"# dork\" to the ${green}Elasticsearch output configuration (YAML)${reset} section and SAVE to update it"
} # End of FLEET


###############################################################################################################

entsearch() {
  # check to make sure that ES is 7.7 or greater
  if [ $(checkversion $VERSION) -lt $(checkversion "7.7.0") ]; then
    echo "${red}[DEBUG]${reset} Enterprise Search started with 7.7+."
    help
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

  # check to see if entsearch-compose.yml already exists.
  if [ -f "entsearch-compose.yml" ]; then
    echo "${red}[DEBUG]${reset} entsearch-compose.yml already exists. Exiting."
    return
  fi

  # check to see if version match
  OLDVERSION="`cat VERSION`"
  if [ $(checkversion $VERSION) -gt $(checkversion $OLDVERSION) ]; then
    echo "${red}[DEBUG]${reset} Version needs to be equal or lower than stack version ${OLDVERSION}"
    exit
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
  echo "${green}[DEBUG]${reset} Added ENTSEARCH_CERTS_DIR to .env"

  # add to elasticsearch.yml
  if [ `grep -c "xpack.security.authc.api_key.enabled" ${WORKDIR}/elasticsearch.yml` = 0 ]; then
    cat >> elasticsearch.yml<<EOF
xpack.security.authc.api_key.enabled: true
EOF
  echo "${green}[DEBUG]${reset} Added xpack.security.authc.api_key.enabled to elasticsearch.yml"
  fi

  # adding action.auto_create_index
  cat >> elasticsearch.yml<<EOF
action.auto_create_index: ".ent-search-*-logs-*,-.ent-search-*,-test-.ent-search-*,+*"
EOF
  echo "${green}[DEBUG]${reset} Added action.auto_create_index to elasticsearch.yml"

  # add to kibana.yml
  if [ $(checkversion $VERSION) -ge $(checkversion "7.10.0") ]; then
    cat >> kibana.yml<<EOF
enterpriseSearch.host: "http://entsearch:3002"
EOF
  echo "${green}[DEBUG]${reset} Added enterpriseSearch.host to kibana.yml"
  fi

  # restart elasticsearch
  for instance in es01 es02 es03 kibana
  do
    docker restart ${instance}>/dev/null 2>&1
    sleep 10
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

# ent_search.auth.default.source: standard
ent_search.ssl.enabled: false

ent_search.listen_host: 0.0.0.0
ent_search.listen_port: 3002
ent_search.external_url: http://localhost:3002

filebeat_log_directory: /var/log/enterprise-search
log_directory: /var/log/enterprise-search
secret_management.encryption_keys: [${ENCRYPTION_KEY}]
secret_session_key: "${ENCRYPTION_KEY}"
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
      - "allow_es_settings_modification=true"
      - "elasticsearch.startup_retry.interval=15"
    volumes: ['./enterprise-search.yml:/usr/share/enterprise-search/config/enterprise-search.yml', 'certs:\$ENTSEARCH_CERTS_DIR', './temp:/temp']
    ports:
      - 3002:3002
    restart: on-failure

volumes: {"certs"}
EOF

  echo "${green}[DEBUG]${reset} Created entsearch-compose.yml"

  docker-compose -f entsearch-compose.yml up -d >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} Started Enterprise Search.  It takes a ${red}WHILE!!${reset} to finish install. Please run docker logs -f entsearch to view progress"
  echo "${green}[DEBUG]${reset} For now please browse to http://localhost:3002 and use enterprise_search and ${PASSWD} to login or kibana if newer versions"
  # echo "${green}[DEBUG]${reset} If you are redirected to http://localhost:3002 then edit elasticstack/enterprise-search.yml and change ent_search.external_url: http://localhost:3002 to localhost to your IP"


  # add monitoring if monitoring is enabled and if enterprise search is 7.16.0+
  if [ $(checkversion $VERSION) -ge $(checkversion "7.16.0") ]; then
    if [ -f "${WORKDIR}/monitor-compose.yml" ]; then
      echo "${green}[DEBUG]${reset} monitoring found and the stack is 7.16.0+ - enabling enterprisesearch monitoring"
      cat >> ${WORKDIR}/metricbeat.yml<<EOF
metricbeat.modules:
- module: enterprisesearch
  metricsets: ["health", "stats"]
  enabled: true
  period: 10s
  hosts: ["http://entsearch:3002"]
  username: "elastic"
  password: "${PASSWD}"
EOF
      docker restart metricbeat >/dev/null 2>&1
      echo "${green}[DEBUG]${reset} metricbeat container restarted"
    fi
  fi

} # End of Enterprise Search

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
  if [ $(checkversion $VERSION) -gt $(checkversion $OLDVERSION) ]; then
    echo "${red}[DEBUG]${reset} Version needs to be equal or lower than stack version ${OLDVERSION}"
    exit
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

  if [ $(checkversion $VERSION) -ge $(checkversion "7.2.0") ]; then
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

} # End of apm function

# LDAP
ldap() {
  # check to see if ${WORKDIR} exits
  if [ ! -d ${WORKDIR} ]; then
    echo "${red}[DEBUG]${reset} Deployment does not exist.  Starting deployment first"
    stack ${VERSION}
    echo "${green}********** Deploying OpenLDAP server and configure the stack with LDAP **********${reset}"
  else
    cd ${WORKDIR}
    echo "${green}********** Deploying OpenLDAP server and configure the stack with LDAP **********${reset}"
  fi

  # check to see if ldap-compose.yml already exists.
  if [ -f "ldap-compose.yml" ]; then
    echo "${red}[DEBUG]${reset} ldap-compose.yml already exists. Exiting."
    exit
  fi

  # grab the elastic password
  grabpasswd

  # check health before continuing
  checkhealth

  # pull image
  pullimage "osixia/openldap"

  # create ldif
  echo "${green}[DEBUG]${reset} Generating ldap.ldif"
  cat > ldap.ldif <<EOF
# Entry 2: cn=user1,dc=example,dc=org
dn: cn=user1,dc=example,dc=org
cn: user1
displayname: user1
givenname: user1
mail: user1@lab.lab
objectclass: inetOrgPerson
objectclass: top
sn: user1
userpassword: user1

# Entry 3: cn=user2,dc=example,dc=org
dn: cn=user2,dc=example,dc=org
cn: user2
displayname: user2
givenname: user2
mail: user2@lab.lab
objectclass: inetOrgPerson
objectclass: top
sn: user2
userpassword: user2

# Entry 4: ou=groups,dc=example,dc=org
dn: ou=groups,dc=example,dc=org
objectclass: organizationalUnit
objectclass: top
ou: groups

# Entry 5: cn=admins,ou=groups,dc=example,dc=org
dn: cn=admins,ou=groups,dc=example,dc=org
cn: admins
objectclass: groupOfUniqueNames
objectclass: top
uniquemember: cn=user1,dc=example,dc=org

# Entry 6: cn=users,ou=groups,dc=example,dc=org
dn: cn=users,ou=groups,dc=example,dc=org
cn: users
objectclass: groupOfUniqueNames
objectclass: top
uniquemember: cn=user2,dc=example,dc=org

# Entry 7: ou=users,dc=example,dc=org
dn: ou=users,dc=example,dc=org
objectclass: organizationalUnit
objectclass: top
ou: users
EOF

  # create ldap-compose.yml
  cat > ldap-compose.yml<<EOF
version: '2.2'

services:
  ldap:
    container_name: ldap
    image: osixia/openldap
    volumes: ['./ldap.ldif:/tmp/ldap.ldif', './temp:/temp']
    ports:
      - 389:389
    restart: on-failure
EOF

  # Start OpenLDAP
  echo "${green}[DEBUG]${reset} Starting OpenLDAP"
  docker-compose -f ldap-compose.yml up -d >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${red}[DEBUG]${reset} Unable to start openldap container"
    exit
  else
    echo "${green}[DEBUG]${reset} OpenLDAP container deployed"
  fi
  
  sleep 10

  # import ldap.ldif
  echo "${green}[DEBUG]${reset} Importing ldap.ldif"
  docker exec ldap ldapadd -x -D "cn=admin,dc=example,dc=org" -w admin -f /tmp/ldap.ldif -H ldap://localhost -ZZ >/dev/null 2>&1
  
  # updating elasticsearch.yml
  echo "${green}[DEBUG]${reset} Updating elasticsearch.yml"
  cat >> elasticsearch.yml<<EOF

xpack:
  security:
    authc:
      realms:
        ldap:
          ldap1:
            order: 0
            url: "ldap://ldap"
            bind_dn: "cn=admin, dc=example, dc=org"
            user_search:
              base_dn: "dc=example,dc=org"
              filter: "(cn={0})"
            group_search:
              base_dn: "dc=example,dc=org"
EOF


  # Creating role_mapping
  echo "${green}[DEBUG]${reset} Creating role_mappings"

  curl -k -u elastic:${PASSWD} -XPUT "https://localhost:9200/_security/role_mapping/ldap-admin" -H 'Content-Type: application/json' -d'
{
    "enabled" : true,
    "roles" : [
      "superuser"
    ],
    "rules" : {
      "all" : [
        {
          "field" : {
            "realm.name" : "ldap1"
          }
        },
        {
          "field" : {
            "groups" : "cn=admins,ou=groups,dc=example,dc=org"
          }
        }
      ]
    },
    "metadata" : { }
  }'  >/dev/null 2>&1

  curl -k -u elastic:${PASSWD} -XPUT "https://localhost:9200/_security/role_mapping/ldap-user" -H 'Content-Type: application/json' -d'
{
    "enabled" : true,
    "roles" : [
      "kibana_admin",
      "beats_admin",
      "machine_learning_admin",
      "watcher_admin",
      "transform_admin",
      "rollup_admin",
      "logstash_admin",
      "ingest_admin",
      "viewer"
    ],
    "rules" : {
      "all" : [
        {
          "field" : {
            "realm.name" : "ldap1"
          }
        },
        {
          "field" : {
            "groups" : "cn=users,ou=groups,dc=example,dc=org"
          }
        }
      ]
    },
    "metadata" : { }
  }' >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Adding xpack.security.authc.realms.ldap.ldap1.secure_bind_password to keystore and restarting instances"
  for instance in es01 es02 es03
  do
    docker exec -i ${instance} bin/elasticsearch-keystore add -xf xpack.security.authc.realms.ldap.ldap1.secure_bind_password <<EOF
admin
EOF
  docker restart ${instance}  >/dev/null 2>&1
  done

  # wait for cluster to be healthy
  checkhealth
  
  echo "${green}[DEBUG]${reset} LDAP configured"
  echo "${green}[DEBUG]${reset} user1/user1 is configured for ldap group admin and has superuser role"
  echo "${green}[DEBUG]${reset} user2/user2 is configured for ldap group users and has *_admin roles"
  echo ""
} # end of ldap

###############################################################################################################

if [ "${1}" != "cleanup" ]; then
  VERSION=${2}
  version ${VERSION}
fi

case ${1} in
  build|start|stack)
    stack ${2}
    ;;
  monitor)
    if [ $(checkversion $VERSION) -ge $(checkversion "6.5.0") ]; then
      monitor ${2}
    else
      help
    fi
    ;;
  snapshot)
    snapshot ${2}
    ;;
  fleet)
    if [ $(checkversion $VERSION) -ge $(checkversion "7.10.0") ]; then
      fleet ${2}
    else
      help
    fi
    ;;
  entsearch)
    if [ $(checkversion $VERSION) -ge $(checkversion "7.7.0") ]; then
      entsearch ${2}
    else
      help
    fi
    ;;
  apm)
    if [ $(checkversion $VERSION) -ge $(checkversion "7.16.0") ]; then
      echo "${green}[DEBUG]${reset} APM server is now part of Fleet Integrations.  Please use fleet"
      echo ""
      help
    else
      apm ${2}
    fi
    ;;
  ldap)
    ldap ${2}
    ;;
  cleanup)
    cleanup
    ;;
  *)
    help
    exit
    ;;
esac



