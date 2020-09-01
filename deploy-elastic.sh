#!/bin/sh

# justin lim <justin@isthecoolest.ninja>

# deploys 3 ES instances & 1 kibana instance in docker containers
# it will create a directory based on the version you input
# http and transport ssl will be enabled and kibana ssl will be enabled and the certificate authority file will be copied out to the directory created.
# temp directory will be created and shared amoung all the containers so if you need to easily move files around like logs or plugins from outside or from container to container you can utilize the temp directory
# notes file will be created with all the username and passwords for this deployment

# colors
red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

# check for binaries
which docker > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "${red}[DEBUG]${reset} You must install docker first"
  exit
fi

which docker-compose > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "${red}[DEBUG}${reset} You must install docker-compose first"
  exit
fi

docker ps -q > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "${red}[DEBUG]${reset} You must be part of the docker group and the daemon must be running"
  exit
fi

# read version
echo "Please enter the version you wish to run (eg. 7.9.0) "
read VERSION

# mkdir on the version and change to dir
mkdir "${VERSION}"
cd "${VERSION}"
PWD=`pwd`

# make a temp directory to share between the containers in case you want to add/remove some troubleshooting things
mkdir -p ${PWD}/temp

# set inital elastic password
ELASTIC_PASSWORD=`openssl rand -base64 29 | tr -d "=+/" | cut -c1-25`
echo "${green}[DEBUG]${reset} Setting temp password for elastic as ${ELASTIC_PASSWORD}"

# create env file
echo "${green}[DEBUG]${reset} Creating .env file"

cat > .env<<EOF
COMPOSE_PROJECT_NAME=es
CERTS_DIR=/usr/share/elasticsearch/config/certificates
KIBANA_CERTS_DIR=/usr/share/kibana/config/certificates
ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
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
      - discovery.seed_hosts=es01,es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
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
    volumes: ['data01:/usr/share/elasticsearch/data', 'certs:\$CERTS_DIR', '${PWD}/temp:/temp']
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
      - discovery.seed_hosts=es01,es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
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
    volumes: ['data02:/usr/share/elasticsearch/data', 'certs:\$CERTS_DIR', '${PWD}/temp:/temp']

  es03:
    container_name: es03
    image: docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
    environment:
      - node.name=es03
      - discovery.seed_hosts=es01,es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
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
    volumes: ['data03:/usr/share/elasticsearch/data', 'certs:\$CERTS_DIR', '${PWD}/temp:/temp']

  kibana:
    container_name: kibana
    image:  docker.elastic.co/kibana/kibana:${VERSION}
    environment:
      - ELASTICSEARCH_HOSTS=https://es01:9200
      - ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES=\$KIBANA_CERTS_DIR/ca/ca.crt
      - SERVER_SSL_CERTIFICATE=\$KIBANA_CERTS_DIR/kibana/kibana.crt
      - SERVER_SSL_KEY=\$KIBANA_CERTS_DIR/kibana/kibana.key
      - SERVER_SSL_ENABLED=true
    volumes: ['${PWD}/kibana.yml:/usr/share/kibana/config/kibana.yml', 'certs:\$KIBANA_CERTS_DIR', '${PWD}/temp:/temp']
    ports:
      - 5601:5601

  wait_until_ready:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.6.1
    command: /usr/bin/true
    depends_on: {"es01": {"condition": "service_healthy"}}

volumes: {"data01", "data02", "data03", "certs"}
EOF

# perform docker pull to pull down the images ahead of its run
echo "${green}[DEBUG]${reset} Pulling images"
docker pull -q docker.elastic.co/elasticsearch/elasticsearch:${VERSION}
if [ $? -ne 0 ]; then
  echo "${red}[DEBUG]${reset} Unable to pull ${VERSION} of elasticsearch. cleanup and exit"
  rm -rf ${PWD}
  exit
fi

docker pull -q docker.elastic.co/kibana/kibana:${VERSION}
if [ $? -ne 0 ]; then
  echo "${red}[DEBUG]${reset} Unable to pull ${VERSION} of kibana.  cleanup and exit"
  rm -rf ${PWD}
  exit
fi

# create certificates
echo "${green}[DEBUG]${reset} Create certificates"
docker-compose -f create-certs.yml run --rm create_certs

# touch kibana.yml for docker-compose up
touch ${PWD}/kibana.yml

# start cluster
echo "${green}[DEBUG]${reset} Starting our deployment"
docker-compose up -d

# wait for cluster to be healthy
while true
do
  if [ `docker run --rm -v es_certs:/certs --network=es_default docker.elastic.co/elasticsearch/elasticsearch:${VERSION} curl -s --cacert /certs/ca/ca.crt -u elastic:${ELASTIC_PASSWORD} https://es01:9200/_cluster/health | grep -c green` = 1 ]; then
  break
  else
    echo "${green}[DEBUG]${reset} Waiting for cluster to turn green to set passwords..."
  fi
  sleep 10
done


# setup passwords
echo "${green}[DEBUG]${reset} Setting passwords and storing it in ${PWD}/notes"
docker exec es01 /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch --url https://localhost:9200" | tee -a notes

PASSWD=`cat notes | grep "PASSWORD elastic" | awk {' print $4 '}`

# create kibana.yml
cat > kibana.yml<<EOF
server.port: 5601
server.host: "0"
elasticsearch.username: "elastic"
elasticsearch.password: "${PASSWD}"
EOF

# restart kibana
echo "${green}[DEBUG]${reset} Restarting kibana to pick up the new elastic password"
docker restart kibanaA

# copy the certificate authority into the homedir for the project
echo "${green}[DEBUG}${reset} Copying the certificate authority into the project folder"
docker exec es01 /bin/bash -c "cp /usr/share/elasticsearch/config/certificates/ca/ca.crt /temp/ca.crt"
mv ${PWD}/temp/ca.crt ${PWD}/

echo "${green}[DEBUG]${reset} Complete.  "
echo ""
echo "To tear down and cleanup later goto \"${PWD}\" and run \"docker-compose down --rmi all -v\" then remove \"${PWD}\""
