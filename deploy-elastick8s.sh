#!/usr/bin/env bash

# justin lim <justin@isthecoolest.ninja>
# 
# version 3.1

# curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/deploy-elastick8s.sh -o deploy-elastick8s.sh
#
# NOTES
# eck 1.2+
#   start of elasticsearchRef
#   ES 6.8+ & 7.1+
#   Beats 7.0+
#   entsearch 7.7+
#   all-in-one operator
# eck 1.4+
#   ES 7.17.3+
# eck 1.6+
#   elastic-agent 7.10+
#   elastic map server 7.11+
# eck 1.7+
#   crds.yaml & operator.yaml
#   fleet 7.14
#   sidecar container stack monitoring started with ES 7.14
# eck 1.9+
#   helm 3.2.0
# eck 2.1+
#   kibana configuration becomre longer and more specific for fleet server
# eck 2.2
#   ES 8.0+

# Starting 7.17 stack container image changed to ubuntu - some fixes are needed due to this

# helm only for 7.14.0-> 7.17.x - older versions not as clean

# items needed:
# jq
# openssl
# docker binary and service
# kubectl
# helm

# set WORKDIR
WORKDIR="${HOME}/elastick8s"

###############################################################################################################
# colors
red=`tput setaf 1`
green=`tput setaf 2`
blue=`tput setaf 14`
reset=`tput sgr0`

###############################################################################################################

# help
help() 
{
  echo ""
  echo "${green}This script will allow you to stand up various elasticstack configurations on suing ECK operator, HELM without the operator, HELM with the operator${reset}"
  echo "${green}You must have jq, helm, docker(installed and running) to use this script${reset}"
  echo "${green}This script was tested on GKE but should work on AKS, EKS as well${reset}"
  echo "${green}Please use ${blue}gke.sh script (https://www.gooksu.com/2022/05/google-cloud-scripts/)${green} to stand up your gke environment before running this script${reset}"
  echo "${green}This script assumes that your kubectl has the proper context to access your k8s environment${reset}"
  echo ""
  echo "${green}For eck operator builds operator is ${red}limited to 1.4 or above${green} and stack is ${red}limited to 7.10.0+${green}. - other limitations per commands${reset}"
  echo "${green}For HELM without operator stack version is ${red}limited to 7.14.0-7.17.x${reset}"
  echo "${green}For NATIVE without operator stack version is ${red}limited to 7.0.0-8.x.x${reset}"
  echo ""
  echo "${green}USAGE:${reset} ./`basename $0` command ...."
  echo ""
  echo "${blue}COMMANDS:${reset}"
  echo "    ${green}operator${reset} - will just stand up the operator only and apply a trial license."
  echo "              Need to specify operator version.  Example: ${green}./`basename $0` operator 2.3.0${reset}"
  echo "    ${green}stack|start|build|eck${reset} - will stand up the ECK Operator, elasticsearch, & kibana with CLUSTER name : ${blue}eck-lab${reset}."
  echo "              Need to specify operator and stack version. Example: ${green}./`basename $0` stack 8.4.1 2.3.0${reset}"
  echo "    ${green}eckldap${reset} - will stand up the ECK Operator, elasticsearch, & kibana with CLUSTER name : ${blue}eck-lab${reset} and an openldap server and configure elasticsearch to auth with openldap."
  echo "    ${green}dedicated${reset} - will stand up the ECK Operator, elasticsearch, & kibana with CLUSTER name : ${blue}eck-lab${reset} with 3 dedicated masters and 3 dedicated data nodes"
  echo "              SAME as stack|start|built but with ${green}dedicated${reset} command"
  echo "    ${green}beats${reset} - will stand up the basic stack + filebeat, metricbeat, packetbeat, & heartbeat"
  echo "              SAME as stack|start|built but with ${green}beats${reset} command"
  echo "    ${green}monitor1${reset} - will stand up the basic stack named ${blue}eck-lab${reset} and a monitoring stack named ${blue}eck-lab-monitor${reset}, filebeat, & metricbeat as PODS to report stack monitoring to ${blue}eck-lab-monitor${reset}"
  echo "              SAME as stack|start|built but with ${green}monitor1${reset} command"
  echo "    ${green}monitor2${reset} - will be the same as ${blue}monitor1${reset} however both filebeat & metricbeat will be a sidecar container inside of elasticsearch & kibana Pods. Limited to ECK ${blue}1.7.0+${reset} & STACK ${blue}7.14.0+${reset}"
  echo "              SAME as stack|start|built but with ${green}monitor2${reset} command"
  echo "    ${green}fleet${reset} - will stand up the basic stack + FLEET Server & elastic-agent as DaemonSet on each ECK node."
  echo "              SAME as stack|start|built but with ${green}fleet${reset} command"
  echo ""
  echo "    ${green}helm${reset} - will stand up elasticsearch and kibana using helm charts without any operator. Currently limited to 7.14.0 - 7.17.x"
  echo "              Need to specify stack version. Example: ${green}./`basename $0` helm 7.17.4${reset}"
  echo "    ${green}helmldap${reset} - will stand up the helm stack + openldap and configure elasticsearch for ldap authentication"
  echo "    ${green}helmbeats${reset} - will stand up the helm stack + filebeat, & metricbeat"
  echo "              SAME as helm but with ${green}helmbeats${reset} command"
  echo "    ${green}helmblogstashbeats${reset} - will stand up the helm stack + logstash, filebeat, & metricbeat. beats will use logstash to send data to ES."
  echo "              SAME as helm but with ${green}helmlogstashbeats${reset} command"
  echo "    ${green}helmmonitor${reset} - will stand up the helm stack & metricbeat for stack monitoring"
  echo "              SAME as helm but with ${green}helmstackmonitor${reset} command"
  echo ""
  echo "    ${green}native${reset} - will stand up elasticsearch and kibana without helm charts & without any operator. Currently limited to 7.0.0 - 8.x.x"
  echo "              Need to specify stack version. Example: ${green}./`basename $0` native 7.17.4${reset}"
  echo "    ${green}nativebeats${reset} - will stand up the helm stack + filebeat, & metricbeat"
  echo "              SAME as helm but with ${green}nativebeats${reset} command"
  echo "    ${green}nativemonitor${reset} - will stand up the helm stack & metricbeat for stack monitoring"
  echo "              SAME as helm but with ${green}nativestackmonitor${reset} command"
  echo ""
  echo "    ${green}cleanup${reset} - will delete all the resources including the ECK operator"
  echo ""
  echo ""
  echo "All yaml files will be stored in ${blue}${WORKDIR}${reset}"
  echo "    ${blue}${WORKDIR}/notes${reset} will contain all endpoint and password information"
  echo "    ${blue}${WORKDIR}/ca.crt${reset} will be the CA used to sign the public certificate"
  echo ""
} # end of help

#############################################################
# FUNCTIONS - HELPER
#############################################################

# FUNCTION - spinner
spinner() {
tput civis

# Clear Line
CL="\e[2K"
# Spinner Character
SPINNER="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

function spinnersub() {
  task=$1
  msg=$2
  while :; do
    jobs %1 > /dev/null 2>&1
    [ $? = 0 ] || {
      printf "${CL}✓ ${task} Done\n"
      break
    }
    for (( i=0; i<${#SPINNER}; i++ )); do
      sleep 0.05
      printf "${CL}${SPINNER:$i:1} ${task} ${msg}\r"
    done
  done
}

msg="${2-InProgress}"
task="${3-$1}"
$1 & spinnersub "$task" "$msg"

tput cnorm

} # end spinner

# FUNCTION - checkjq
checkjq() {
  if ! [ -x "$(command -v jq)" ]; then
    echo "${red}[DEBUG]${reset} jq is not installed.  Please install jq and try again."
    exit
  else
    echo "${green}[DEBUG]${reset} jq found"
  fi
} # end checkjq

# FUNCTION - checkopenssl
checkopenssl() {
  if ! [ -x "$(command -v openssl)" ]; then
    echo "${red}[DEBUG]${reset} openssl is not installed.  Please install openssl and try again."
    exit
  else
    echo "${green}[DEBUG]${reset} openssl found"
  fi
} # end checkopenssl

# FUNCTION - checkdocker
checkdocker() {
  # check to ensure docker is installed or exit
  docker info >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${red}[DEBUG]${reset} Docker is not running or you are not part of the docker group.  Please install docker and ensure that you are part of the docker group and try again."
    exit
  else
    echo "${green}[DEBUG]${reset} docker found & running"
  fi
} # end checkdocker

# FUNCTION - kubectl
checkkubectl()
{
  if [ `kubectl version 2>/dev/null | grep -c "Client Version"` -lt 1 ]; then
    echo "${red}[DEBUG]${reset} kubectl is not installed.  Please install kubectl and try again."
    exit
  else
    echo "${green}[DEBUG]${reset} kubectl found"
  fi
  if [ `kubectl version 2>/dev/null | grep -c "Server Version"` -lt 1 ]; then
    echo "${red}[DEBUG]${reset} kubectl is not connecting to any kubernetes environment"
    echo "${red}[DEBUG]${reset} if you did not setup your k8s environment.  Please configure your kubernetes context and try again"
    exit
  fi
} # end checkubectl

# FUNCTION - helm
checkhelm()
{
  if ! [ -x "$(command -v helm)" ]; then
    echo "${red}[DEBUG]${reset} helm is not installed.  Please install helm and try again. https://helm.sh/docs/intro/install/"
    exit
  else
    echo "${green}[DEBUG]${reset} helm found"
  fi
} # end checkhelm

# FUNCTION - checkversion
checkversion() 
{
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
} # end checkversion

# FUNCTION - checkdir
checkdir()
{
  # check to see if the directory exists should not since this is the start
  if [ -d ${WORKDIR} ]; then
    echo "${red}[DEBUG]${reset} Looks like ${WORKDIR} already exists."
    echo "${red}[DEBUG]${reset} Please run ${blue}`basename $0` cleanup${reset} before trying again"
    echo ""
    help
    exit
  fi # end of if to check if WORKDIR exist

  # create directorys and files
  mkdir -p ${WORKDIR}
  cd ${WORKDIR}
  mkdir temp
  if [ ! -z ${VERSION} ]; then
    echo ${VERSION} > VERSION
  fi
  if [ ! -z ${ECKVERSION} ]; then
    echo ${ECKVERSION} > ECKVERSION
  fi

} # end checkdir

# FUNCTION - checkcontainerimage
checkcontainerimage() {
  # check to see if the container image exists or not
  docker manifest inspect ${1} >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "${red}[DEBUG]${reset} Image ${blue}${1}${reset} does not exist.  Please verify and try again"
    exit
  else
    echo "${green}[DEBUG]${reset} container image ${blue}${1}${reset} is valid"
  fi
} # end checkcontainerimage

# FUNCTION - checkrequiredversion
checkrequiredversion() {
  # manually limiting eck version to 1.4 or greater
  if [ $(checkversion $ECKVERSION) -lt $(checkversion "1.4.0") ]; then
    echo "${red}[DEBUG]${reset} Script is limited to operator 1.4.0 and higher"
    echo ""
    help
    exit
  else
    if [ $(checkversion $ECKVERSION) -lt $(checkversion "1.7.0") ]; then
      if curl -sL --fail https://download.elastic.co/downloads/eck/${ECKVERSION}/all-in-one.yaml -o /dev/null; then
        echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} version validated."
      else
        echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} version is invalid."
        echo ""
        help
        exit
      fi
    elif [ $(checkversion $ECKVERSION) -ge $(checkversion "1.7.0") ]; then
      if curl -sL --fail https://download.elastic.co/downloads/eck/${ECKVERSION}/crds.yaml -o /dev/null; then
        echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} version validated."
      else
        echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} version is invalid."
        echo ""
        help
        exit
      fi
    fi
  fi
  if [ $(checkversion $ECKVERSION) -lt $(checkversion "2.2.0") -a $(checkversion $VERSION) -ge $(checkversion "8.0.0") ]; then
    echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} Can not run 8.x.  Please use operator 2.2.0+"
    echo ""
    help
    exit
  fi

  # manually limiting elasticsearch version to 7.10.0 or greater
  if [ $(checkversion $VERSION) -lt $(checkversion "7.10.0") ]; then
    echo "${red}[DEBUG]${reset} This command is limited to stack version 7.10.0 and higher"
    echo ""
    help
    exit
  fi

  echo "${green}[DEBUG]${reset} This might take a while.  In another window you can ${blue}watch -n2 kubectl get all${reset} or ${blue}kubectl get events -w${reset} to watch the stack being stood up"
  echo ""

} # end checkrequiredversion

# FUNCTION - checkrequiredversionhelm
checkrequiredversionhelm() {
  # manually limiting version to 7.14.0+ to -8.0.0
  if [ $(checkversion $VERSION) -lt $(checkversion "7.14.0") -o $(checkversion $VERSION) -ge $(checkversion "8.0.0") ]; then
    echo "${red}[DEBUG]${reset} This command is limited to stack version 7.14.0+ & < 8.0.0"
    echo ""
    help
    exit
  fi 
} # end checkrequiredversionhelm

# FUNCTION - checkrequiredversionnative
checkrequiredversionnative() {
  # manually limiting version to value
  if [ $(checkversion $VERSION) -lt $(checkversion "${1}") ]; then
    echo "${red}[DEBUG]${reset} This command is limited to stack version ${1}"
    echo ""
    help
    exit
  fi 
} # end checkrequiredversionnative

# FUNCTION - checkhealth
checkhealth() {
  sleep 3
  while true
  do
    tt=`kubectl get ${1} ${2} -ojson | jq -r '.status.'${3}''`
    if [ "${tt}" == "${4}" ]; then
      sleep 2
      echo "${green}[DEBUG]${reset} ${2} ${1} is showing ${4} replicas ready${reset}"
      echo ""
      kubectl get ${1} ${2} | sed "s/^/                     /"
      echo ""
      break
    else
      echo "${red}[DEBUG]${reset} ${2} is starting. Checking again in 10 seconds.  If this does not finish in few minutes something is wrong. CTRL-C please"
      spinner "sleep 10" "Sleeping" "Sleeping 10 seconds"
    fi
  done
} # end checkhealth

############################################################

# FUNCTION - createsummary
createsummary()
{
  # FOR ECK deployments
  if [ -e ${WORKDIR}/ECK ]; then
    unset PASSWORD
    c=0
    while [ "${PASSWORD}" = "" ]
    do
      PASSWORD=$(kubectl get secret ${1}-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')
      sleep 1
      ((c++))
      if [ $c = 30 ]; then
        echo "${red}[DEBUG]${reset} Unable to get elasticsearch password."
        exit
      fi
    done
    echo "${green}[DEBUG]${reset} Grabbed elastic password for ${1}: ${blue}${PASSWORD}${reset}"
    echo "${1} elastic password: ${PASSWORD}" >> notes
  
    unset ESIP
    c=0
    while [ "${ESIP}" = "" -o "${ESIP}" = "<pending>" ]
    do
      ESIP=`kubectl get service | grep ${1}-es-http | awk '{ print $4 }'`
      sleep 1
      ((c++))
      if [ $c = 30 ]; then
        echo "${red}[DEBUG]${reset} Unable to get elasticsearch endpoint."
        exit
      fi
    done
    echo "${green}[DEBUG]${reset} Grabbed elasticsearch endpoint for  ${1}: ${blue}https://${ESIP}:9200${reset}"
    echo "${1} elasticsearch endpoint: https://${ESIP}:9200" >> notes
  
    unset KIBANAIP
    c=0
    while [ "${KIBANAIP}" = "" -o "${KIBANAIP}" = "<pending>" ]
    do
      KIBANAIP=`kubectl get service | grep ${1}-kb-http | awk '{ print $4 }'`
      sleep 1
      ((c++))
      if [ $c = 30 ]; then
        echo "${red}[DEBUG]${reset} Unable to get kibana endpoint."
        exit
      fi
    done
    echo "${green}[DEBUG]${reset} Grabbed kibana endpoint for ${1}: ${blue}https://${KIBANAIP}:5601${reset}"
    echo "${1} kibana endpoint: https://${KIBANAIP}:5601" >> notes

    kubectl get secrets ${1}-es-http-certs-public -o jsonpath="{.data.ca\.crt}" | base64 -d > ${WORKDIR}/ca.crt

  # FOR HELM deployments
  elif [ -e ${WORKDIR}/HELM ]; then
    unset PASSWORD
    c=0
    while [ "${PASSWORD}" = "" ]
    do
      PASSWORD=$(kubectl get secrets elastic-credentials -o go-template='{{.data.password | base64decode}}')
      sleep 1
      ((c++))
      if [ $c = 30 ]; then
        echo "${red}[DEBUG]${reset} Unable to get elasticsearch password."
        exit
      fi
    done
    echo "${green}[DEBUG]${reset} Grabbed elastic password for ${1}: ${blue}${PASSWORD}${reset}"
    echo "${1} elastic password: ${PASSWORD}" >> notes
  
    unset ESIP
    c=0
    while [ "${ESIP}" = "" -o "${ESIP}" = "<pending>" ]
    do
      ESIP=`kubectl get service | grep ${1}-es-default | grep -v headless | awk '{ print $4 }'`
      sleep 1
      ((c++))
      if [ $c = 30 ]; then
        echo "${red}[DEBUG]${reset} Unable to get elasticsearch endpoint."
        exit
      fi
    done
    echo "${green}[DEBUG]${reset} Grabbed elasticsearch endpoint for  ${1}: ${blue}https://${ESIP}:9200${reset}"
    echo "${1} elasticsearch endpoint: https://${ESIP}:9200" >> notes
  
    unset KIBANAIP
    c=0
    while [ "${KIBANAIP}" = "" -o "${KIBANAIP}" = "<pending>" ]
    do
      KIBANAIP=`kubectl get service | grep helm-lab-kb-kibana | awk '{ print $4 }'`
      sleep 1
      ((c++))
      if [ $c = 30 ]; then
        echo "${red}[DEBUG]${reset} Unable to get kibana endpoint."
        exit
      fi
    done
    echo "${green}[DEBUG]${reset} Grabbed kibana endpoint for ${1}: ${blue}https://${KIBANAIP}:5601${reset}"
    echo "${1} kibana endpoint: https://${KIBANAIP}:5601" >> notes

  # FOR NATIVE deployments
  elif [ -e ${WORKDIR}/NATIVE ]; then
    unset PASSWORD
    c=0
    while [ "${PASSWORD}" = "" ]
    do
      PASSWORD=$(kubectl get secrets elastic-credentials -o go-template='{{.data.password | base64decode}}')
      sleep 1
      ((c++))
      if [ $c = 30 ]; then
        echo "${red}[DEBUG]${reset} Unable to get elasticsearch password."
        exit
      fi
    done
    echo "${green}[DEBUG]${reset} Grabbed elastic password for ${1}: ${blue}${PASSWORD}${reset}"
    echo "${1} elastic password: ${PASSWORD}" >> notes
  
    unset ESIP
    c=0
    while [ "${ESIP}" = "" -o "${ESIP}" = "<pending>" ]
    do
      ESIP=`kubectl get service | grep ${1}-default | grep -v headless | awk '{ print $4 }'`
      sleep 1
      ((c++))
      if [ $c = 30 ]; then
        echo "${red}[DEBUG]${reset} Unable to get elasticsearch endpoint."
        exit
      fi
    done
    echo "${green}[DEBUG]${reset} Grabbed elasticsearch endpoint for  ${1}: ${blue}https://${ESIP}:9200${reset}"
    echo "${1} elasticsearch endpoint: https://${ESIP}:9200" >> notes
  
    unset KIBANAIP
    c=0
    while [ "${KIBANAIP}" = "" -o "${KIBANAIP}" = "<pending>" ]
    do
      KIBANAIP=`kubectl get service | grep native-lab-kibana | awk '{ print $4 }'`
      sleep 1
      ((c++))
      if [ $c = 30 ]; then
        echo "${red}[DEBUG]${reset} Unable to get kibana endpoint."
        exit
      fi
    done
    echo "${green}[DEBUG]${reset} Grabbed kibana endpoint for ${1}: ${blue}https://${KIBANAIP}:5601${reset}"
    echo "${1} kibana endpoint: https://${KIBANAIP}:5601" >> notes
  fi

  echo ""
} # end createsummary

# FUNCTION - summary
summary()
{
  if [ -e ${WORKDIR}/ECK ]; then
    echo ""
    echo "${green}[SUMMARY]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset}"
    echo ""
    kubectl get all | sed "s/^/                     /"
    echo ""
    echo "${green}[SUMMARY]${reset} STACK INFO:"
    while read line
    do
      string1=`echo $line | awk -F": " '{ print $1 }'`
      string2=`echo $line | awk -F": " '{ print $2 }'`
      echo "${string1}: ${blue}${string2}${reset}"
    done < ${WORKDIR}/notes

    echo ""
    echo "${green}[SUMMARY]${reset} ${blue}ca.crt${reset} is located in ${blue}${WORKDIR}/ca.crt${reset}"
    echo ""
    echo "${green}[NOTE]${reset} If you missed the summary its also in ${blue}${WORKDIR}/notes${reset}"
    echo "${green}[NOTE]${reset} You can start logging into kibana but please give things few minutes for proper startup and letting components settle down."
    echo ""
  elif [ -e ${WORKDIR}/HELM ]; then
    echo ""
    echo "${green}[SUMMARY]${reset} HELM STACK ${blue}${VERSION}${reset}"
    echo ""
    kubectl get all | sed "s/^/                     /"
    echo ""
    echo "${green}[SUMMARY]${reset} HELM STACK INFO:"
    while read line
    do
      string1=`echo $line | awk -F": " '{ print $1 }'`
      string2=`echo $line | awk -F": " '{ print $2 }'`
      echo "${string1}: ${blue}${string2}${reset}"
    done < ${WORKDIR}/notes

    echo ""
    echo "${green}[SUMMARY]${reset} ${blue}ca.crt${reset} is located in ${blue}${WORKDIR}/ca.crt${reset}"

  elif [ -e ${WORKDIR}/NATIVE ]; then
    echo ""
    echo "${green}[SUMMARY]${reset} NATIVE STACK ${blue}${VERSION}${reset}"
    echo ""
    kubectl get all | sed "s/^/                     /"
    echo ""
    echo "${green}[SUMMARY]${reset} NATIVE STACK INFO:"
    while read line
    do
      string1=`echo $line | awk -F": " '{ print $1 }'`
      string2=`echo $line | awk -F": " '{ print $2 }'`
      echo "${string1}: ${blue}${string2}${reset}"
    done < ${WORKDIR}/notes

    echo ""
    echo "${green}[SUMMARY]${reset} ${blue}ca.crt${reset} is located in ${blue}${WORKDIR}/ca.crt${reset}"

  fi  
} # end summary

# FUNCTION - beatsetup
beatsetup()
{

  echo "${green}[DEBUG]${reset} Running setup for ${1}.."
  kubectl delete pod beats-setup >/dev/null 2>&1
  kubectl run -it beats-setup --image=docker.elastic.co/beats/${1}:${VERSION} -- sh -c "${1} setup -E output.elasticsearch.hosts=\"${ESIP}:9200\" -E output.elasticsearch.protocol=https -E output.elasticsearch.username=elastic -E output.elasticsearch.password=${PASSWORD} -E output.elasticsearch.ssl.verification_mode=none -E setup.kibana.host=\"${KIBANAIP}:5601\" -E setup.kibana.protocol=https -E setup.kibana.username=elastic -E setup.kibana.password=${PASSWORD} -E setup.kibana.ssl.verification_mode=none -E setup.ilm.overwrite=true" >/dev/null 2>&1
  kubectl delete pod beats-setup >/dev/null 2>&1

} # end beatsetup

# FUNCTION - createcerts
createcerts() {
  echo ""
  echo "${green}[DEBUG]${reset} Creating ca.crt and certificate/key for ${1}"
  docker rm -f ${1}-certs >/dev/null 2>&1
  # hard coding for 7.17.5 container... 8.x containers changed
  docker run --name ${1}-certs -i -w /app \
  docker.elastic.co/elasticsearch/elasticsearch:7.17.5 \
    /bin/sh -c " \
      elasticsearch-certutil ca --silent --pem -out /app/ca.zip && \
      unzip /app/ca.zip -d /app && \
      elasticsearch-certutil cert --silent --pem -out /app/${1}.zip --name ${1} --dns ${1} --ca-cert /app/ca/ca.crt --ca-key /app/ca/ca.key && \
      unzip /app/${1}.zip -d /app 
  " >/dev/null 2>&1
  mkdir ${WORKDIR}/${1}-certs >/dev/null 2>&1
  docker cp ${1}-certs:/app/ca/ca.crt ${WORKDIR}/${1}-certs/
  docker cp ${1}-certs:/app/ca/ca.key ${WORKDIR}/${1}-certs
  docker cp ${1}-certs:/app/${1}/${1}.crt ${WORKDIR}/${1}-certs
  docker cp ${1}-certs:/app/${1}/${1}.key ${WORKDIR}/${1}-certs
  docker rm -f ${1}-certs >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating secret ${1}-certificates"
  kubectl create secret generic ${2} --from-file=${WORKDIR}/${1}-certs/ca.crt --from-file=${WORKDIR}/${1}-certs/${1}.crt --from-file=${WORKDIR}/${1}-certs/${1}.key >/dev/null 2>&1

} # end createcerts

#############################################################
# FUNCTIONS - MAIN
#############################################################

# FUNCTION - cleanup
cleanup()
{
  # make sure to name all yaml files as .yaml so that it can be picked up during cleanup
  echo ""
  echo "${green}********** Cleaning up **********${reset}"
  echo ""
  
  if [ -e ${WORKDIR}/ECK ]; then
    for item in `ls -1t ${WORKDIR}/*.yaml 2>/dev/null`
    do
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}${item}${reset}"
      kubectl delete -f ${item} > /dev/null 2>&1
    done
    kubectl delete secret fleet-server-agent-http-certs-public >/dev/null 2>&1
    if [ -e ${WORKDIR}/openldap.yaml ]; then
      kubectl delete -f ${WORKDIR}/openldap.yaml >/dev/null 2>&1
      kubectl delete secret openldap openldap-certificates ldapbindpw-secret >/dev/null 2>&1
    fi
  elif [ -e ${WORKDIR}/HELM ]; then
    echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}helm-lab elasticsearch${reset}"
    helm uninstall elasticsearch > /dev/null 2>&1
    kubectl delete pvc helm-lab-es-default-helm-lab-es-default-0 > /dev/null 2>&1
    kubectl delete pvc helm-lab-es-default-helm-lab-es-default-1 > /dev/null 2>&1
    kubectl delete pvc helm-lab-es-default-helm-lab-es-default-2 > /dev/null 2>&1
    kubectl delete secrets elastic-certificates > /dev/null 2>&1
    kubectl delete secrets elastic-credentials > /dev/null 2>&1
    kubectl delete secrets elastic-endpoint > /dev/null 2>&1
    
    echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}helm-lab kibana${reset}"
    helm uninstall helm-lab-kb > /dev/null 2>&1
    kubectl delete secrets kibana-credentials > /dev/null 2>&1
    kubectl delete secrets kibana-encryptionkey > /dev/null 2>&1
    kubectl delete secrets kibana-certificates  > /dev/null 2>&1

    if [ -e ${WORKDIR}/fb-values.yaml ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}helm-lab filebeat${reset}"
      helm uninstall helm-lab-fb > /dev/null 2>&1
      kubectl delete secrets beats-credentials > /dev/null 2>&1
    fi
    if [ -e ${WORKDIR}/mb-values.yaml ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}helm-lab metricbeat${reset}"
      helm uninstall kube-state-metrics > /dev/null 2>&1
      helm uninstall helm-lab-mb > /dev/null 2>&1
      kubectl delete secrets beats-credentials > /dev/null 2>&1
    fi
    if [ -e ${WORKDIR}/ls-values.yaml ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}helm-lab logstash${reset}"
      helm uninstall helm-lab-ls > /dev/null 2>&1
      kubectl delete pvc helm-lab-ls-logstash-helm-lab-ls-logstash-0 > /dev/null 2>&1
    fi
    if [ -e ${WORKDIR}/openldap.yaml ]; then
      kubectl delete -f ${WORKDIR}/openldap.yaml >/dev/null 2>&1
      kubectl delete secret openldap openldap-certificates ldapbindpw-secret >/dev/null 2>&1
    fi
  elif [ -e ${WORKDIR}/NATIVE ]; then
    echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}native-lab kibana${reset}"
    kubectl delete -f ${WORKDIR}/kibana.yaml > /dev/null 2>&1
    kubectl delete secrets kibana-encryptionkey > /dev/null 2>&1
    kubectl delete secrets kibana-certificates  > /dev/null 2>&1
    kubectl delete secrets kibana-credentials > /dev/null 2>&1
    echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}native-lab elasticsearch${reset}"
    kubectl delete -f ${WORKDIR}/elasticsearch.yaml > /dev/null 2>&1
    kubectl delete pvc native-lab-default-native-lab-default-0 > /dev/null 2>&1
    kubectl delete pvc native-lab-default-native-lab-default-1 > /dev/null 2>&1
    kubectl delete pvc native-lab-default-native-lab-default-2 > /dev/null 2>&1
    kubectl delete secrets elastic-certificates > /dev/null 2>&1
    kubectl delete secrets elastic-credentials > /dev/null 2>&1

    if [ -e ${WORKDIR}/filebeat-kubernetes.yaml ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}native-lab filebeat${reset}"
      kubectl delete -f ${WORKDIR}/filebeat-kubernetes.yaml > /dev/null 2>&1
      kubectl delete secrets beats-credentials > /dev/null 2>&1
    fi
    if [ -e ${WORKDIR}/metricbeat-kubernetes.yaml ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}native-lab metricbeat${reset}"
      kubectl delete -f ${WORKDIR}/kube-state-metrics/examples/standard > /dev/null 2>&1
      kubectl delete -f ${WORKDIR}/metricbeat-kubernetes.yaml > /dev/null 2>&1
      kubectl delete secrets beats-credentials > /dev/null 2>&1
    fi
    if [ -e ${WORKDIR}/openldap.yaml ]; then
      kubectl delete -f ${WORKDIR}/openldap.yaml >/dev/null 2>&1
      kubectl delete secret openldap openldap-certificates ldapbindpw-secret >/dev/null 2>&1
    fi
  fi
  rm -rf ${WORKDIR} > /dev/null 2>&1
  echo ""
  echo "${green}[DEBUG]${reset} All cleanedup"
  echo ""
} # end cleanup

# FUNCTION - operator
operator() 
{
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} OPERATOR **************${reset}"
  echo ""
  
  touch ${WORKDIR}/ECK

  # all version checks complete & directory structures created starting operator
  if [ $(checkversion $ECKVERSION) -lt $(checkversion "1.7.0") ]; then # if version is less than 1.7.0
    echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} downloading operator: all-in-one.yaml"
    if curl -sL --fail https://download.elastic.co/downloads/eck/${ECKVERSION}/all-in-one.yaml -o all-in-one.yaml; then # if curl is successful
      kubectl apply -f ${WORKDIR}/all-in-one.yaml > /dev/null 2>&1
    else
      echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} Failed to get all-in-one.yaml - check network/version?"
      echo ""
      help
      exit
    fi
  else # if eckversion is not less than 1.7.0
    echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} downloading crds: crds.yaml"
    if curl -fsSL https://download.elastic.co/downloads/eck/${ECKVERSION}/crds.yaml -o crds.yaml; then
      kubectl create -f ${WORKDIR}/crds.yaml > /dev/null 2>&1
    else
      echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} Failed to get crds.yaml - check network/version?"
      echo ""
      help
      exit
    fi
    echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} downloading operator: operator.yaml"
    if curl -fsSL https://download.elastic.co/downloads/eck/${ECKVERSION}/operator.yaml -o operator.yaml; then
      kubectl create -f ${WORKDIR}/operator.yaml > /dev/null 2>&1
    else
      echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} Failed to get operator.yaml - check network/version?"
      echo ""
      help
      exit
    fi
  fi

  while true
  do
    if [ "`kubectl -n elastic-system get pod | grep elastic-operator | awk '{ print $3 }'`" = "Running" ]; then
      echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} OPERATOR is ${green}HEALTHY${reset}"
      echo ""
      kubectl -n elastic-system get all | sed "s/^/                     /"
      echo ""
      break
    else
      echo "${red}[DEBUG]${reset} ECK Operator is starting.  Checking again in 10 seconds.  If the operator does not goto Running status in few minutes something is wrong. CTRL-C please"
      sleep 10
      echo ""
    fi
  done
  
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} Creating license.yaml"
  # apply trial licence
  cat >> ${WORKDIR}/license.yaml<<EOF
apiVersion: v1
kind: Secret
metadata:
  name: eck-trial-license
  namespace: elastic-system
  labels:
    license.k8s.elastic.co/type: enterprise_trial
  annotations:
    elastic.co/eula: accepted 
EOF
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} Applying trial license"
  kubectl apply -f ${WORKDIR}/license.yaml  > /dev/null 2>&1

} # end operator

# FUNCTION - stackbuild
stackbuild() {
  echo ""
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} STACK ${BLUE}${VERSION}${green} CLUSTER ${blue}${1}${reset} **************${reset}"
  echo ""

  # create elasticsearch.yaml
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER ${blue}${1}${reset} Creating elasticsearch.yaml"
  cat >> ${WORKDIR}/elasticsearch-${1}.yaml <<EOF
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: ${1}
spec:
  version: ${VERSION}
  nodeSets:
  - name: default
    config:
      node.roles: ["master", "data", "ingest", "ml", "remote_cluster_client", "transform"]
      xpack.security.authc.api_key.enabled: true
    podTemplate:
      metadata:
        labels:
          scrape: es
      spec:
        containers:
        - name: elasticsearch
          resources:
            requests:
              memory: 2Gi
              cpu: 1
            limits:
              memory: 2Gi
              cpu: 1
        initContainers:
        - name: sysctl
          securityContext:
            privileged: true
            runAsUser: 0
          command: ['sh', '-c', 'sysctl -w vm.max_map_count=262144']
    count: 3
  http:
    service:
      spec:
        type: LoadBalancer
EOF

  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER ${blue}${1}${reset} Starting elasticsearch cluster."

  kubectl apply -f ${WORKDIR}/elasticsearch-${1}.yaml > /dev/null 2>&1

  # checkeshealth
  checkhealth "statefulset" "${1}-es-default" "readyReplicas" "3"

  # create kibana.yaml
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER  ${blue}${1}${reset} Creating kibana.yaml"
    cat >> ${WORKDIR}/kibana-${1}.yaml <<EOF
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: ${1}
spec:
  version: ${VERSION}
  count: 1
  elasticsearchRef:
    name: "${1}"
  http:
    service:
      spec:
        type: LoadBalancer
  podTemplate:
    metadata:
      labels:
        scrape: kb
EOF

  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER  ${blue}${1}${reset} Starting kibana."

  kubectl apply -f ${WORKDIR}/kibana-${1}.yaml > /dev/null 2>&1

  #checkkbhealth
  checkhealth "deployment" "${1}-kb" "readyReplicas" "1"

  createsummary ${1}

} # end stackbuild

# FUNCTION - eckldap
eckldap() {
  
  echo "${green}[DEBUG]${reset} Adding OPENLDAP server with TLS and patching ES deployment for ldap realm"
  echo ""

  sleep 5
  echo "${green}[DEBUG]${reset} Creating patch for elasticsearch deployment(starting with this since it will take the longest)"
  cat > ${WORKDIR}/elasticsearch-eck-lab-patch.yaml <<EOF
spec:
  secureSettings:
  - secretName: ldapbindpw-secret
  nodeSets:
  - config:
      node.roles:
      - master
      - data
      - ingest
      - ml
      - remote_cluster_client
      - transform
      xpack.security.authc.api_key.enabled: true
      xpack.security.authc.realms.ldap.ldap1:
        order: 0
        url: "ldaps://openldap:1636"
        bind_dn: "cn=admin, dc=example, dc=org"
        user_search:
          base_dn: "dc=example,dc=org"
          filter: "(cn={0})"
        group_search:
          base_dn: "dc=example,dc=org"
        ssl:
          certificate_authorities: [ "config/openldap-certs/ca.crt" ]
          verification_mode: none
    count: 3
    name: default
    podTemplate:
      spec:
        containers:
        - name: elasticsearch
          volumeMounts:
          - name: openldap-certs
            mountPath: /usr/share/elasticsearch/config/openldap-certs
        volumes:
        - name: openldap-certs
          secret:
            secretName: openldap-certificates
            defaultMode: 0640
EOF
  echo "${green}[DEBUG]${reset} Applying the patch to eck-lab."
  kubectl patch elasticsearch eck-lab --type merge --patch-file ${WORKDIR}/elasticsearch-eck-lab-patch.yaml >/dev/null 2>&1
  sleep 2

  echo "${green}[DEBUG]${reset} Creating ldapbindpw secret to make the keystore entry for bindpw"
  cat > ${WORKDIR}/ldapbindpw-secret.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: ldapbindpw-secret
type: Opaque
data:
  xpack.security.authc.realms.ldap.ldap1.secure_bind_password: YWRtaW5wYXNzd29yZA==
EOF
  kubectl apply -f ${WORKDIR}/ldapbindpw-secret.yaml >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating ca.crt and server certificate/key for openldap"
  createcerts openldap openldap-certificates

  echo "${green}[DEBUG]${reset} Creating secret for users and passwords"
  kubectl create secret generic openldap --from-literal=adminpassword=adminpassword --from-literal=users=user01,user02 --from-literal=passwords=password01,password02 >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating openldap.yaml"
  cat > ${WORKDIR}/openldap.yaml<<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openldap
  labels:
    app.kubernetes.io/name: openldap
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: openldap
  replicas: 1
  template:
    metadata:
      labels:
        app.kubernetes.io/name: openldap
    spec:
      containers:
        - name: openldap
          image: docker.io/bitnami/openldap:latest
          imagePullPolicy: "Always"
          env:
            - name: LDAP_ADMIN_USERNAME
              value: "admin"
            - name: LDAP_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  key: adminpassword
                  name: openldap
            - name: LDAP_USERS
              valueFrom:
                secretKeyRef:
                  key: users
                  name: openldap
            - name: LDAP_PASSWORDS
              valueFrom:
                secretKeyRef:
                  key: passwords
                  name: openldap
            - name: LDAPTLS_REQCERT
              value: "never"
            - name: LDAP_ENABLE_TLS
              value: "yes"
            - name: LDAP_TLS_CA_FILE
              value: "/opt/bitnami/openldap/certs/ca.crt"
            - name: LDAP_TLS_CERT_FILE
              value: "/opt/bitnami/openldap/certs/openldap.crt"
            - name: LDAP_TLS_KEY_FILE
              value: "/opt/bitnami/openldap/certs/openldap.key"
          volumeMounts:
            - name: openldap-certificates
              mountPath: /opt/bitnami/openldap/certs
              readOnly: true
          ports:
            - name: tcp-ldap
              containerPort: 1636
      volumes:
        - name: openldap-certificates
          secret:
            secretName: openldap-certificates
            defaultMode: 0660

---
apiVersion: v1
kind: Service
metadata:
  name: openldap
  labels:
    app.kubernetes.io/name: openldap
spec:
  type: ClusterIP
  ports:
    - name: tcp-ldap
      port: 1636
      targetPort: tcp-ldap
  selector:
    app.kubernetes.io/name: openldap
EOF

  echo "${green}[DEBUG]${reset} Creating openldap server"
  kubectl apply -f ${WORKDIR}/openldap.yaml >/dev/null 2>&1

  sleep 5

  echo "${green}[DEBUG]${reset} Creating role mappings"
  until curl -s -k -u "elastic:${PASSWORD}" -XPUT "https://${ESIP}:9200/_security/role_mapping/ldap-admin" -H 'Content-Type: application/json' -d'
{"enabled":true,"roles":["superuser"],"rules":{"all":[{"field":{"realm.name":"ldap1"}}]},"metadata":{}}' >/dev/null 2>&1
    do
      sleep 2
    done


  echo "${green}[DEBUG]${red} Patching elasticsearch takes a while so please ensure that all ES pods have been recreated before trying to login with ldap${reset}"

} # end eckldap

# FUNCTION - dedicated
dedicated() 
{
  echo ""
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} STACK ${BLUE}${VERSION}${green} CLUSTER ${blue}${1}${reset} with DEDICATED masters and data nodes **************${reset}"
  echo ""

  # create elasticsearch.yaml
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER ${blue}${1}${reset} Creating elasticsearch.yaml"
  cat >> ${WORKDIR}/elasticsearch-${1}.yaml <<EOF
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: ${1}
spec:
  version: ${VERSION}
  nodeSets:
  - name: master
    config:
      node.roles: master
      xpack.security.authc.api_key.enabled: true
    podTemplate:
      metadata:
        labels:
          scrape: es
      spec:
        containers:
        - name: elasticsearch
          resources:
            requests:
              memory: 2Gi
              cpu: 1
            limits:
              memory: 2Gi
              cpu: 1
        initContainers:
        - name: sysctl
          securityContext:
            privileged: true
            runAsUser: 0
          command: ['sh', '-c', 'sysctl -w vm.max_map_count=262144']
    count: 3
  - name: data
    config:
      node.roles: ["data", "ingest", "ml", "remote_cluster_client", "transform"]
      xpack.security.authc.api_key.enabled: true
    podTemplate:
      metadata:
        labels:
          scrape: es
      spec:
        containers:
        - name: elasticsearch
          resources:
            requests:
              memory: 2Gi
              cpu: 1
            limits:
              memory: 2Gi
              cpu: 1
        initContainers:
        - name: sysctl
          securityContext:
            privileged: true
            runAsUser: 0
          command: ['sh', '-c', 'sysctl -w vm.max_map_count=262144']
    count: 3
  http:
    service:
      spec:
        type: LoadBalancer
EOF

  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER ${blue}${1}${reset} Starting elasticsearch cluster."

  kubectl apply -f ${WORKDIR}/elasticsearch-${1}.yaml > /dev/null 2>&1

  # checkeshealth
  checkhealth "statefulset" "${1}-es-master" "readyReplicas" "3"
  checkhealth "statefulset" "${1}-es-data" "readyReplicas" "3"

  # create kibana.yaml
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER  ${blue}${1}${reset} Creating kibana.yaml"
    cat >> ${WORKDIR}/kibana-${1}.yaml <<EOF
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: ${1}
spec:
  version: ${VERSION}
  count: 1
  elasticsearchRef:
    name: "${1}"
  http:
    service:
      spec:
        type: LoadBalancer
  podTemplate:
    metadata:
      labels:
        scrape: kb
EOF

  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER  ${blue}${1}${reset} Starting kibana."

  kubectl apply -f ${WORKDIR}/kibana-${1}.yaml > /dev/null 2>&1

  #checkkbhealth
  checkhealth "deployment" "${1}-kb" "readyReplicas" "1"

  createsummary ${1}

} # end dedicated

# FUNCTION - beats
beats()
{
  echo ""
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} STACK ${BLUE}${VERSION}${green} BEATS **************${reset}"
  echo ""

  # Create and apply metricbeat-rbac
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} Creating BEATS crds"
  cat >> ${WORKDIR}/beats-crds.yaml<<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: metricbeat
rules:
- apiGroups:
  - ""
  resources:
  - nodes
  - namespaces
  - events
  - pods
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - "extensions"
  resources:
  - replicasets
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - apps
  resources:
  - statefulsets
  - deployments
  - replicasets
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes/stats
  verbs:
  - get
- nonResourceURLs:
  - /metrics
  verbs:
  - get
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: metricbeat
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: metricbeat
subjects:
- kind: ServiceAccount
  name: metricbeat
  namespace: default
roleRef:
  kind: ClusterRole
  name: metricbeat
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: filebeat
rules:
- apiGroups: [""] # "" indicates the core API group
  resources:
  - namespaces
  - pods
  - nodes
  verbs:
  - get
  - watch
  - list
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: filebeat
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: filebeat
subjects:
- kind: ServiceAccount
  name: filebeat
  namespace: default
roleRef:
  kind: ClusterRole
  name: filebeat
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: heartbeat
subjects:
- kind: ServiceAccount
  name: heartbeat
  namespace: default
roleRef:
  kind: ClusterRole
  name: heartbeat
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: heartbeat
subjects:
- kind: ServiceAccount
  name: heartbeat
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: heartbeat
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: heartbeat
  labels:
    k8s-app: heartbeat
rules:
- apiGroups: [""]
  resources:
  - nodes
  - namespaces
  - pods
  - services
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources:
    - replicasets
  verbs: ["get", "list", "watch"]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: heartbeat
  namespace: default
  labels:
    k8s-app: heartbeat
EOF

  kubectl apply -f ${WORKDIR}/beats-crds.yaml > /dev/null 2>&1

  # Create and apply metricbeat-rbac
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} Creating BEATS"
  cat >> ${WORKDIR}/beats.yaml<<EOF
apiVersion: beat.k8s.elastic.co/v1beta1
kind: Beat
metadata:
  name: metricbeat
spec:
  type: metricbeat
  version: ${VERSION}
  elasticsearchRef:
    name: ${1}
  config:
    metricbeat:
      autodiscover:
        providers:
        - hints:
            default_config: {}
            enabled: "true"
          node: \${NODE_NAME}
          type: kubernetes
      modules:
      - module: system
        period: 10s
        metricsets:
        - cpu
        - load
        - memory
        - network
        - process
        - process_summary
        process:
          include_top_n:
            by_cpu: 5
            by_memory: 5
        processes:
        - .*
      - module: system
        period: 1m
        metricsets:
        - filesystem
        - fsstat
        processors:
        - drop_event:
            when:
              regexp:
                system:
                  filesystem:
                    mount_point: ^/(sys|cgroup|proc|dev|etc|host|lib)($|/)
      - module: kubernetes
        period: 10s
        node: \${NODE_NAME}
        hosts:
        - https://\${NODE_NAME}:10250
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        ssl:
          verification_mode: none
        metricsets:
        - node
        - system
        - pod
        - container
        - volume
    processors:
    - add_cloud_metadata: {}
    - add_host_metadata: {}
  daemonSet:
    podTemplate:
      spec:
        serviceAccountName: metricbeat
        automountServiceAccountToken: true # some older Beat versions are depending on this settings presence in k8s context
        containers:
        - args:
          - -e
          - -c
          - /etc/beat.yml
          - -system.hostfs=/hostfs
          name: metricbeat
          volumeMounts:
          - mountPath: /hostfs/sys/fs/cgroup
            name: cgroup
          - mountPath: /var/run/docker.sock
            name: dockersock
          - mountPath: /hostfs/proc
            name: proc
          env:
          - name: NODE_NAME
            valueFrom:
              fieldRef:
                fieldPath: spec.nodeName
        dnsPolicy: ClusterFirstWithHostNet
        hostNetwork: true # Allows to provide richer host metadata
        securityContext:
          runAsUser: 0
        terminationGracePeriodSeconds: 30
        volumes:
        - hostPath:
            path: /sys/fs/cgroup
          name: cgroup
        - hostPath:
            path: /var/run/docker.sock
          name: dockersock
        - hostPath:
            path: /proc
          name: proc
---
apiVersion: beat.k8s.elastic.co/v1beta1
kind: Beat
metadata:
  name: filebeat
spec:
  type: filebeat
  version: ${VERSION}
  elasticsearchRef:
    name: ${1}
  kibanaRef:
    name: ${1}
  config:
    filebeat:
      autodiscover:
        providers:
        - type: kubernetes
          node: \${NODE_NAME}
          hints:
            enabled: true
            default_config:
              type: container
              paths:
              - /var/log/containers/*\${data.kubernetes.container.id}.log
    processors:
    - add_cloud_metadata: {}
    - add_host_metadata: {}
  daemonSet:
    podTemplate:
      spec:
        serviceAccountName: filebeat
        automountServiceAccountToken: true
        terminationGracePeriodSeconds: 30
        dnsPolicy: ClusterFirstWithHostNet
        hostNetwork: true # Allows to provide richer host metadata
        containers:
        - name: filebeat
          securityContext:
            runAsUser: 0
            # If using Red Hat OpenShift uncomment this:
            #privileged: true
          volumeMounts:
          - name: varlogcontainers
            mountPath: /var/log/containers
          - name: varlogpods
            mountPath: /var/log/pods
          - name: varlibdockercontainers
            mountPath: /var/lib/docker/containers
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
        volumes:
        - name: varlogcontainers
          hostPath:
            path: /var/log/containers
        - name: varlogpods
          hostPath:
            path: /var/log/pods
        - name: varlibdockercontainers
          hostPath:
            path: /var/lib/docker/containers
---
apiVersion: beat.k8s.elastic.co/v1beta1
kind: Beat
metadata:
  name: packetbeat
spec:
  type: packetbeat
  version: ${VERSION}
  elasticsearchRef:
    name: ${1}
  kibanaRef:
    name: ${1}
  config:
    packetbeat.interfaces.device: any
    packetbeat.protocols:
    - type: dns
      ports: [53]
      include_authorities: true
      include_additionals: true
    - type: http
      ports: [80, 8000, 8080, 9200, 5601]
    packetbeat.flows:
      timeout: 30s
      period: 10s
    processors:
    - add_cloud_metadata: {}
    - add_host_metadata: {}
  daemonSet:
    podTemplate:
      spec:
        terminationGracePeriodSeconds: 30
        hostNetwork: true
        automountServiceAccountToken: true # some older Beat versions are depending on this settings presence in k8s context
        dnsPolicy: ClusterFirstWithHostNet
        containers:
        - name: packetbeat
          securityContext:
            runAsUser: 0
            capabilities:
              add:
              - NET_ADMIN
---
apiVersion: beat.k8s.elastic.co/v1beta1
kind: Beat
metadata:
  name: heartbeat
spec:
  type: heartbeat
  version: ${VERSION}
  elasticsearchRef:
    name: ${1}
  config:
    heartbeat.monitors:
    - type: tcp
      name: "eck-lab elastic endpoint"
      schedule: '@every 5s'
      hosts: ["eck-lab-es-http.default.svc:9200"]
    - type: http
      name: "eck-lab kibana endpoint"
      schedule: '@every 5s'
      hosts: ["https://eck-lab-kb-http.default.svc:5601"]
      ssl.verification_mode: none
      check.request.method: HEAD
  deployment:
    replicas: 1
    podTemplate:
      spec:
        securityContext:
          runAsUser: 0
EOF

  kubectl apply -f ${WORKDIR}/beats.yaml  > /dev/null 2>&1

  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} filebeat, metricbeat, packetbeat, & heartbeat deployed"
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} Please wait a few minutes for the beats to become healthy. (it will restart 3-4 times before it becomes healthy) & for the data to start showing"

  echo ""

} # end beats

# FUNCTION - monitor1
monitor1()
{
  echo ""
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} STACK ${BLUE}${VERSION}${green} Stack Monitoring with BEATS in Pods **************${reset}"
  echo ""
  
  # remove labels from eck-lab-montor pods
  # is this needed?
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} Removing scrape label from monitoring pods"
  for item in `kubectl get pods --no-headers -o custom-columns=":metadata.name" | grep eck-lab-monitor`
  do
    kubectl label pod ${item} scrape- > /dev/null 2>&1
  done
  sleep 10

  # Create and apply monitor1.yaml
  cat >> ${WORKDIR}/monitor1.yaml<<EOF
apiVersion: beat.k8s.elastic.co/v1beta1
kind: Beat
metadata:
  name: metricbeat
spec:
  type: metricbeat
  version: ${VERSION}
  elasticsearchRef:
    name: eck-lab-monitor
  kibanaRef:
    name: eck-lab-monitor
  config:
    metricbeat:
      autodiscover:
        providers:
          - type: kubernetes
            scope: cluster
            hints.enabled: true
            templates:
              - condition:
                  contains:
                    kubernetes.labels.scrape: es
                config:
                  - module: elasticsearch
                    metricsets:
                      - ccr
                      - cluster_stats
                      - enrich
                      - index
                      - index_recovery
                      - index_summary
                      - ml_job
                      - node_stats
                      - shard
                    period: 10s
                    hosts: "https://\${data.host}:\${data.ports.https}"
                    username: \${MONITORED_ES_USERNAME}
                    password: \${MONITORED_ES_PASSWORD}
                    # WARNING: disables TLS as the default certificate is not valid for the pod FQDN
                    # TODO: switch this to "certificate" when available: https://github.com/elastic/beats/issues/8164
                    ssl.verification_mode: "none"
                    xpack.enabled: true
              - condition:
                  contains:
                    kubernetes.labels.scrape: kb
                config:
                  - module: kibana
                    metricsets:
                      - stats
                    period: 10s
                    hosts: "https://\${data.host}:\${data.ports.https}"
                    username: \${MONITORED_ES_USERNAME}
                    password: \${MONITORED_ES_PASSWORD}
                    # WARNING: disables TLS as the default certificate is not valid for the pod FQDN
                    # TODO: switch this to "certificate" when available: https://github.com/elastic/beats/issues/8164
                    ssl.verification_mode: "none"
                    xpack.enabled: true
    processors:
    - add_cloud_metadata: {}
    logging.json: true
  deployment:
    podTemplate:
      spec:
        serviceAccountName: metricbeat
        automountServiceAccountToken: true
        # required to read /etc/beat.yml
        securityContext:
          runAsUser: 0
        containers:
        - name: metricbeat
          env:
          - name: MONITORED_ES_USERNAME
            value: elastic
          - name: MONITORED_ES_PASSWORD
            valueFrom:
              secretKeyRef:
                key: elastic
                name: ${1}-es-elastic-user
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: metricbeat
rules:
- apiGroups: [""] # "" indicates the core API group
  resources:
  - namespaces
  - pods
  - nodes
  verbs:
  - get
  - watch
  - list
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: metricbeat
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: metricbeat
subjects:
- kind: ServiceAccount
  name: metricbeat
  namespace: default
roleRef:
  kind: ClusterRole
  name: metricbeat
  apiGroup: rbac.authorization.k8s.io
---
# filebeat resources
apiVersion: beat.k8s.elastic.co/v1beta1
kind: Beat
metadata:
  name: filebeat
spec:
  type: filebeat
  version: ${VERSION}
  elasticsearchRef:
    name: eck-lab-monitor
  kibanaRef:
    name: eck-lab-monitor
  config:
    filebeat:
      autodiscover:
        providers:
        - type: kubernetes
          node: \${NODE_NAME}
          hints:
            enabled: true
            default_config:
              type: container
              paths:
              - /var/log/containers/*\${data.kubernetes.container.id}.log
    processors:
    - add_cloud_metadata: {}
    - add_host_metadata: {}
    logging.json: true
  daemonSet:
    podTemplate:
      spec:
        serviceAccountName: filebeat
        automountServiceAccountToken: true
        terminationGracePeriodSeconds: 30
        dnsPolicy: ClusterFirstWithHostNet
        hostNetwork: true # Allows to provide richer host metadata
        securityContext:
          runAsUser: 0
          # If using Red Hat OpenShift uncomment this:
          #privileged: true
        containers:
        - name: filebeat
          volumeMounts:
          - name: varlogcontainers
            mountPath: /var/log/containers
          - name: varlogpods
            mountPath: /var/log/pods
          - name: varlibdockercontainers
            mountPath: /var/lib/docker/containers
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
        volumes:
        - name: varlogcontainers
          hostPath:
            path: /var/log/containers
        - name: varlogpods
          hostPath:
            path: /var/log/pods
        - name: varlibdockercontainers
          hostPath:
            path: /var/lib/docker/containers
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: filebeat
rules:
- apiGroups: [""] # "" indicates the core API group
  resources:
  - namespaces
  - pods
  - nodes
  verbs:
  - get
  - watch
  - list
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: filebeat
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: filebeat
subjects:
- kind: ServiceAccount
  name: filebeat
  namespace: default
roleRef:
  kind: ClusterRole
  name: filebeat
  apiGroup: rbac.authorization.k8s.io
EOF

  kubectl apply -f ${WORKDIR}/monitor1.yaml > /dev/null 2>&1

  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} Stack monitoring with BEATS in PODS deployed"
  echo ""
} # end monitor1

# FUNCTION - monitor2
monitor2()
{
  echo ""
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} STACK ${BLUE}${VERSION}${green} Stack Monitoring with BEATS in sidecar containers **************${reset}"
  echo ""

  # create elasticsearch-eck-lab.yaml
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER ${blue}${1}${reset} Creating elasticsearch.yaml"
  cat >> monitor2.yaml <<EOF
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: ${1}
spec:
  version: ${VERSION}
  monitoring:
    metrics:
      elasticsearchRefs:
      - name: eck-lab-monitor
    logs:
      elasticsearchRefs:
      - name: eck-lab-monitor
  nodeSets:
  - name: default
    config:
      node.roles: ["master", "data", "ingest", "ml", "remote_cluster_client"]
      xpack.security.authc.api_key.enabled: true
    podTemplate:
      metadata:
        labels:
          scrape: es
      spec:
        initContainers:
        - name: sysctl
          securityContext:
            privileged: true
            runAsUser: 0
          command: ['sh', '-c', 'sysctl -w vm.max_map_count=262144']
    count: 3
  http:
    service:
      spec:
        type: LoadBalancer
---
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: ${1}
spec:
  version: ${VERSION}
  elasticsearchRef:
    name: ${1}
  monitoring:
    metrics:
      elasticsearchRefs:
      - name: eck-lab-monitor
    logs:
      elasticsearchRefs:
      - name: eck-lab-monitor
  count: 1
  http:
    service:
      spec:
        type: LoadBalancer
  podTemplate:
    metadata:
      labels:
        scrape: kb
EOF

  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER ${blue}${1}${reset} Starting elasticsearch & kibana."

  kubectl apply -f ${WORKDIR}/monitor2.yaml > /dev/null 2>&1

  # checkkbhealth
  checkhealth "statefulset" "${1}-es-default" "readyReplicas" "3"
  checkhealth "deployment" "${1}-kb" "readyReplicas" "1"

  createsummary "${1}"
  echo ""

# notes
# you can create a normal deployment and patch it using kubectl patch kibana eck-lab --type merge -p '{"spec":{"monitoring":{"logs":{"elasticsearchRefs":[{"name":"eck-lab-monitor"}]},"metrics":{"elasticsearchRefs":[{"name":"eck-lab-monitor"}]}}}}' to change it to sidecar monitoring
#

} # end monitor2

# FUNCTION - fleet
fleet()
{
  echo ""
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} STACK ${blue}${VERSION}${green} Fleet Server & elastic-agent **************${reset}"
  echo ""

  # patch kibana
  echo "${green}[DEBUG]${reset} Patching kibana to set fleet settings"
  if [ $(checkversion $ECKVERSION) -lt $(checkversion "2.1.0") ]; then
    kubectl patch kibana eck-lab --type merge -p '{"spec":{"config":{"xpack.fleet.agentPolicies":[{"is_default_fleet_server":true,"name":"Default Fleet Server on ECK policy","package_policies":[{"name":"fleet_server-1","package":{"name":"fleet_server"}}]},{"is_default":true,"name":"Default Elastic Agent on ECK policy","package_policies":[{"name":"system-1","package":{"name":"system"}},{"name":"kubernetes-1","package":{"name":"kubernetes"}}],"unenroll_timeout":900}],"xpack.fleet.agents.elasticsearch.host":"https://eck-lab-es-http.default.svc:9200","xpack.fleet.agents.fleet_server.hosts":["https://fleet-server-agent-http.default.svc:8220"],"xpack.fleet.packages":[{"name":"kubernetes","version":"latest"}]}}}'
  elif [ $(checkversion $ECKVERSION) -ge $(checkversion "2.1.0") ]; then
    kubectl patch kibana eck-lab --type merge -p '{"spec":{"config":{"xpack.fleet.agentPolicies":[{"id":"eck-fleet-server","is_default_fleet_server":true,"monitoring_enabled":["logs","metrics"],"name":"Fleet Server on ECK policy","namespace":"default","package_policies":[{"id":"fleet_server-1","name":"fleet_server-1","package":{"name":"fleet_server"}}]},{"id":"eck-agent","is_default":true,"monitoring_enabled":["logs","metrics"],"name":"Elastic Agent on ECK policy","namespace":"default","package_policies":[{"name":"system-1","package":{"name":"system"}},{"name":"kubernetes-1","package":{"name":"kubernetes"}}],"unenroll_timeout":900}],"xpack.fleet.agents.elasticsearch.host":"https://eck-lab-es-http.default.svc:9200","xpack.fleet.agents.fleet_server.hosts":["https://fleet-server-agent-http.default.svc:8220"],"xpack.fleet.packages":[{"name":"system","version":"latest"},{"name":"elastic_agent","version":"latest"},{"name":"fleet_server","version":"latest"},{"name":"kubernetes","version":"0.14.0"}]}}}'  > /dev/null 2>&1
  fi
  echo "${green}[DEBUG]${reset} Sleeping for 60 seconds to wait for kibana to be updated with the patch"
  spinner "sleep 60" "Sleeping" "Sleeping 60 seconds waiting for kibana"
  echo ""

  # create fleet-server.yaml
  echo "${green}[DEBUG]${reset} Creating fleet.yaml"
  cat >> fleet.yaml<<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: fleet-server
rules:
- apiGroups: [""]
  resources:
  - pods
  - namespaces
  - nodes
  verbs:
  - get
  - watch
  - list
- apiGroups: ["coordination.k8s.io"]
  resources:
  - leases
  verbs:
  - get
  - create
  - update
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fleet-server
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: fleet-server
subjects:
- kind: ServiceAccount
  name: fleet-server
  namespace: default
roleRef:
  kind: ClusterRole
  name: fleet-server
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: elastic-agent
rules:
- apiGroups: [""]
  resources:
  - pods
  - nodes
  - namespaces
  - events
  - services
  - configmaps
  verbs:
  - get
  - watch
  - list
- apiGroups: ["coordination.k8s.io"]
  resources:
  - leases
  verbs:
  - get
  - create
  - update
- nonResourceURLs:
  - "/metrics"
  verbs:
  - get
- apiGroups: ["extensions"]
  resources:
    - replicasets
  verbs: 
  - "get"
  - "list"
  - "watch"
- apiGroups:
  - "apps"
  resources:
  - statefulsets
  - deployments
  - replicasets
  verbs:
  - "get"
  - "list"
  - "watch"
- apiGroups:
  - ""
  resources:
  - nodes/stats
  verbs:
  - get
- apiGroups:
  - "batch"
  resources:
  - jobs
  verbs:
  - "get"
  - "list"
  - "watch"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: elastic-agent
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: elastic-agent
subjects:
- kind: ServiceAccount
  name: elastic-agent
  namespace: default
roleRef:
  kind: ClusterRole
  name: elastic-agent
  apiGroup: rbac.authorization.k8s.io
EOF
  # due to https://github.com/elastic/cloud-on-k8s/issues/5323
#  if [ $(checkversion $ECKVERSION) -lt $(checkversion "2.1.0") -o $(checkversion $VERSION) -lt $(checkversion "7.17.0") ]; then
  if [ $(checkversion $VERSION) -ge $(checkversion "7.17.0") ]; then
    cat >> fleet.yaml<<EOF
---
apiVersion: agent.k8s.elastic.co/v1alpha1
kind: Agent
metadata:
  name: fleet-server
spec:
  version: ${VERSION}
  kibanaRef:
    name: ${1}
  elasticsearchRefs:
  - name: ${1}
  mode: fleet
  fleetServerEnabled: true
  deployment:
    replicas: 1
    podTemplate:
      spec:
        serviceAccountName: elastic-agent
        automountServiceAccountToken: true
        securityContext:
          runAsUser: 0
        containers:
        - name: agent
          command:
          - bash
          - -c 
          - |
            #!/usr/bin/env bash
            set -e
            if [[ -f /mnt/elastic-internal/elasticsearch-association/default/eck-lab/certs/ca.crt ]]; then
              cp /mnt/elastic-internal/elasticsearch-association/default/eck-lab/certs/ca.crt /usr/local/share/ca-certificates
              update-ca-certificates
            fi
            /usr/bin/tini -- /usr/local/bin/docker-entrypoint -e
  http:
    service:
      spec:
        type: LoadBalancer
---
apiVersion: agent.k8s.elastic.co/v1alpha1
kind: Agent
metadata:
  name: elastic-agent
  namespace: default
spec:
  version: ${VERSION}
  kibanaRef:
    name: ${1}
  fleetServerRef:
    name: fleet-server
  mode: fleet
  daemonSet:
    podTemplate:
      spec:
        serviceAccountName: elastic-agent
        automountServiceAccountToken: true
        securityContext:
          runAsUser: 0
        containers:
        - name: agent
          command:
          - bash
          - -c 
          - |
            #!/usr/bin/env bash
            set -e
            if [[ -f /mnt/elastic-internal/elasticsearch-association/default/eck-lab/certs/ca.crt ]]; then
              cp /mnt/elastic-internal/elasticsearch-association/default/eck-lab/certs/ca.crt /usr/local/share/ca-certificates
              update-ca-certificates
            fi
            /usr/bin/tini -- /usr/local/bin/docker-entrypoint -e
EOF
  else
#  elif [ $(checkversion $ECKVERSION) -ge $(checkversion "2.1.0") ]; then
  cat >> fleet.yaml<<EOF
---
apiVersion: agent.k8s.elastic.co/v1alpha1
kind: Agent
metadata:
  name: fleet-server
  namespace: default
spec:
  version: ${VERSION}
  kibanaRef:
    name: ${1}
  elasticsearchRefs:
  - name: ${1}
  mode: fleet
  fleetServerEnabled: true
  deployment:
    replicas: 1
    podTemplate:
      spec:
        serviceAccountName: elastic-agent
        automountServiceAccountToken: true
        securityContext:
          runAsUser: 0
---
apiVersion: agent.k8s.elastic.co/v1alpha1
kind: Agent
metadata:
  name: elastic-agent
  namespace: default
spec:
  version: ${VERSION}
  kibanaRef:
    name: ${1}
  fleetServerRef:
    name: fleet-server
  mode: fleet
  daemonSet:
    podTemplate:
      spec:
        serviceAccountName: elastic-agent
        automountServiceAccountToken: true
        securityContext:
          runAsUser: 0
EOF
  fi

  echo "${green}[DEBUG]${reset} STACK VERSION: ${blue}${VERSION}${reset} Starting fleet-server & elastic-agents."

  kubectl apply -f ${WORKDIR}/fleet.yaml > /dev/null 2>&1

  # checkfleethealth
  #checkhealth "agent" "elastic-agent"
  sleep 30

  # get fleet url
  unset FLEETIP
  while [ "${FLEETIP}" = "" -o "${FLEETIP}" = "<pending>" ]
  do
    FLEETIP=`kubectl get service | grep fleet-server-agent-http | awk '{ print $4 }'`
    echo "${green}[DEBUG]${reset} Grabbing Fleet Server endpoint (external): ${blue}https://${FLEETIP}:8220${reset}"
    sleep 3
  done
  echo "${1} Fleet Server endpoint: https://${FLEETIP}:8220" >> notes



  # for Fleet Server 8.2+ - Add external output with fingerprint and verification_mode
  if [ $(checkversion $VERSION) -ge $(checkversion "8.2.0") ]; then

    echo "${green}[DEBUG]${reset} Waiting 30 seconds for fleet server to calm down to set the external output"
    spinner "sleep 30" "Sleeping" "Sleeping 30 seconds waiting for fleet server"

    echo "${green}[DEBUG]${reset} Setting Fleet Server URL"

    # need to set fleet server url
    generate_post_data()
    {
      cat <<EOF
{
  "fleet_server_hosts":["https://${FLEETIP}:8220","https://fleet-server-agent-http.default.svc:8220"]
}
EOF
    }

    curl -k -u "elastic:${PASSWORD}" -X PUT "https://${KIBANAIP}:5601/api/fleet/settings" \
    --header 'kbn-xsrf: true' \
    --header 'Content-Type: application/json' \
    -d "$(generate_post_data)" >/dev/null 2>&1

    sleep 10

    echo "${green}[DEBUG]${reset} Setting Elasticsearch URL and CA Fingerprint"

    # generate fingerprint
    FINGERPRINT=`openssl x509 -fingerprint -sha256 -noout -in ${WORKDIR}/ca.crt | awk -F"=" {' print $2 '} | sed s/://g`

    generate_post_data()
    {
      cat <<EOF
{
  "name": "external",
  "type": "elasticsearch",
  "hosts": ["https://${ESIP}:9200"],
  "is_default": false,
  "is_default_monitoring": false,
  "ca_trusted_fingerprint": "${FINGERPRINT}",
  "config_yaml": "ssl:\n  verification_mode: none"
}
EOF
    }

    curl -k -u "elastic:${PASSWORD}" -X POST "https://${KIBANAIP}:5601/api/fleet/outputs" \
    --header 'kbn-xsrf: true' \
    --header 'Content-Type: application/json' \
    -d "$(generate_post_data)" >/dev/null 2>&1

    sleep 10
    
    echo "${green}[DEBUG]${reset} Setting Fleet default output"

    # Lets go ahead and create an External agent policy
    # get id for the external output
    EXTID=`curl -s -k -u "elastic:${PASSWORD}" https://${KIBANAIP}:5601/api/fleet/outputs | jq -r '.items[]| select(.name=="external")|.id'`


    generate_post_data()
    {
      cat <<EOF
{
  "name":"External Agent Policy",
  "description":"If you want to use elastic-agent from outside of the k8s cluster",
  "namespace":"default",
  "monitoring_enabled":["logs","metrics"],
  "data_output_id":"${EXTID}",
  "monitoring_output_id":"${EXTID}"
}
EOF
    }

    curl -k -u "elastic:${PASSWORD}" -X POST "https://${KIBANAIP}:5601/api/fleet/agent_policies?sys_monitoring=true" \
    --header 'kbn-xsrf: true' \
    --header 'Content-Type: application/json' \
    -d "$(generate_post_data)" >/dev/null 2>&1

    sleep 10

    echo "${green}[DEBUG]${reset} Output: external created.  You can use this output for elastic-agent from outside of k8s cluster."
    echo "${green}[DEBUG]${reset} Please create a new agent policy using the external output if you want to use elastic-agent from outside of k8s cluster."
    echo "${green}[DEBUG]${reset} Please use https://${FLEETIP}:8220 with --insecure to register your elastic-agent if you are coming from outside of k8s cluster."
    echo ""

  fi # end if for fleet server 8.2+ external output

  # for Fleet Server 8.1 - 1 output no changes needed

  # for Fleet Server 8.0 - 1 output sometimes the output is not set correctly. going to fix
  if [ $(checkversion $VERSION) -ge $(checkversion "8.0.0") ] && [ $(checkversion $VERSION) -lt $(checkversion "8.2.0") ]; then
    
    echo "${green}[DEBUG]${reset} Waiting 30 seconds for fleet server to calm down to set the output"
    spinner "sleep 30" "Sleeping" "Sleeping 30 seconds waiting for fleet server"

    generate_post_data()
    {
      cat <<EOF
{
  "name":"default",
  "type":"elasticsearch",
  "hosts":["https://eck-lab-es-http.default.svc:9200"],
  "is_default":true,
  "is_default_monitoring":true,
  "config_yaml":"",
  "ca_trusted_fingerprint":""
}
EOF
    }

    curl -k -u "elastic:${PASSWORD}" -X PUT "https://${KIBANAIP}:5601/api/fleet/outputs/fleet-default-output" \
    --header 'kbn-xsrf: true' \
    --header 'Content-Type: application/json' \
    -d "$(generate_post_data)" >/dev/null 2>&1


  fi # end if for fleet server 8.0-8.1

  # for Fleet Server < 8.0 only 1 output can be set - do not need to do anything

} # end fleet

# FUNCTION - helmstack
helmstack()
{
  touch ${WORKDIR}/HELM

  echo ""
  echo "${green} ********** Deploying ELASTIC STACK ${blue}${VERSION}${green} with HELM CHARTS - without ECK operator **************${reset}"
  echo ""
  
  # add helm repo and update it
  helm repo add elastic https://helm.elastic.co >/dev/null 2>&1
  helm update repo elastic >/dev/null 2>&1

  # Create elastic users password and create secret
  echo "${green}[DEBUG]${reset} Create elastic user password and create a secret"
  PASSWORD=`openssl rand -base64 29 | tr -d "=+/" | cut -c1-25`
  kubectl create secret generic elastic-credentials --from-literal=password=$(echo $PASSWORD) --from-literal=username=elastic >/dev/null 2>&1

  # Create certificates
  echo "${green}[DEBUG]${reset} Create certificates for the stack and add create secrets"
  createcerts ${1}-es-default elastic-certificates
  createcerts ${1}-kb-default kibana-certificates

  # Create es-values.yaml
  echo "${green}[DEBUG]${reset} Create es-values.yaml"
  cat > ${WORKDIR}/es-values.yaml <<EOF
---
clusterName: "${1}-es"
nodeGroup: "default"
  
# The service that non master groups will try to connect to when joining the cluster
# This should be set to clusterName + "-" + nodeGroup for your master group
masterService: "${1}-es-default"
    
# Elasticsearch roles that will be applied to this nodeGroup
# These will be set as environment variables. E.g. node.master=true
roles:
  master: "true"
  ingest: "true"
  data: "true"
  remote_cluster_client: "true"
  ml: "true"

esConfig:
  elasticsearch.yml: |
    xpack.security.enabled: true
    xpack.security.transport.ssl.enabled: true
    xpack.security.transport.ssl.verification_mode: certificate
    xpack.security.transport.ssl.certificate_authorities: /usr/share/elasticsearch/config/certs/ca.crt
    xpack.security.transport.ssl.certificate: /usr/share/elasticsearch/config/certs/${1}-es-default.crt
    xpack.security.transport.ssl.key: /usr/share/elasticsearch/config/certs/${1}-es-default.key
    xpack.security.http.ssl.enabled: true
    xpack.security.http.ssl.certificate_authorities: /usr/share/elasticsearch/config/certs/ca.crt
    xpack.security.http.ssl.certificate: /usr/share/elasticsearch/config/certs/${1}-es-default.crt
    xpack.security.http.ssl.key: /usr/share/elasticsearch/config/certs/${1}-es-default.key

extraEnvs:
  - name: ELASTIC_PASSWORD
    valueFrom:
      secretKeyRef:
        name: elastic-credentials
        key: password

secretMounts:
  - name: elastic-certificates
    secretName: elastic-certificates
    path: /usr/share/elasticsearch/config/certs

podAnnotations:
  co.elastic.logs.json-logging/json.keys_under_root: "true"
  co.elastic.logs.json-logging/json.add_error_key: "true"
  co.elastic.logs.json-logging/json.message_key: "message"

volumeClaimTemplate:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 2Gi

protocol: https

service:
  enabled: true
  type: LoadBalancer
  publishNotReadyAddresses: false
  nodePort: ""
  httpPortName: http
  transportPortName: transport
EOF

  echo "${green}[DEBUG]${reset} Starting elasticsearch"
  helm install elasticsearch elastic/elasticsearch -f ${WORKDIR}/es-values.yaml --set imageTag=${VERSION} >/dev/null 2>&1

  checkhealth "statefulset" "${1}-es-default" "readyReplicas" "3"
  echo ""

  # start kibana

  # create encryptionkey and its secret
  echo "${green}[DEBUG]${reset} Creating kibana encryption key secret"
  encryptionkey=`openssl rand -base64 29 | tr -d "=+/" | cut -c1-32`
  kubectl create secret generic kibana-encryptionkey --from-literal=encryptionkey=$(echo $encryptionkey) >/dev/null 2>&1

  # Create kb-values.yaml
  echo "${green}[DEBUG]${reset} Create kb-vaules.yaml"
  cat > ${WORKDIR}/kb-values.yaml <<EOF
---
elasticsearchHosts: "https://${1}-es-default:9200"

# Extra environment variables to append to this nodeGroup
# This will be appended to the current 'env:' key. You can use any of the kubernetes env
# syntax here
extraEnvs:
  - name: "NODE_OPTIONS"
    value: "--max-old-space-size=1800"
  - name: 'ELASTICSEARCH_USERNAME'
    valueFrom:
      secretKeyRef:
        name: elastic-credentials
        key: username
  - name: 'ELASTICSEARCH_PASSWORD'
    valueFrom:
      secretKeyRef:
        name: elastic-credentials
        key: password
  - name: 'KIBANA_ENCRYPTION_KEY'
    valueFrom:
      secretKeyRef:
        name: kibana-encryptionkey
        key: encryptionkey

# A list of secrets and their paths to mount inside the pod
# This is useful for mounting certificates for security and for mounting
# the X-Pack license
secretMounts:
  - name: kibana-certificates
    secretName: kibana-certificates
    path: /usr/share/kibana/config/certs

podAnnotations:
  co.elastic.logs.json-logging/json.keys_under_root: "true"
  co.elastic.logs.json-logging/json.add_error_key: "true"
  co.elastic.logs.json-logging/json.message_key: "message"
  
protocol: https

# Allows you to add any config files in /usr/share/kibana/config/
# such as kibana.yml
kibanaConfig:
  kibana.yml: |
    server.ssl:
      enabled: true
      key: /usr/share/kibana/config/certs/${1}-kb-default.key
      certificate: /usr/share/kibana/config/certs/${1}-kb-default.crt
    xpack.security.encryptionKey: \${KIBANA_ENCRYPTION_KEY}
    xpack.encryptedSavedObjects.encryptionKey: \${KIBANA_ENCRYPTION_KEY}
    elasticsearch.ssl:
      certificateAuthorities: /usr/share/kibana/config/certs/ca.crt
      verificationMode: none

service:
  type: LoadBalancer
  loadBalancerIP: ""
  port: 5601
  nodePort: ""
  labels: {}
  annotations:
    {}
  loadBalancerSourceRanges:
    []
  httpPortName: http
EOF

  echo "${green}[DEBUG]${reset} Starting kibana"
  helm install ${1}-kb elastic/kibana -f ${WORKDIR}/kb-values.yaml --set imageTag=${VERSION} >/dev/null 2>&1

  checkhealth "deployment" "${1}-kb-kibana" "readyReplicas" "1"
  echo ""


  createsummary ${1}

  # apply trial license
  echo "${green}[DEBUG]${reset} Applying trial license."
  until curl -k --silent -u "elastic:${PASSWORD}" -XPOST "https://$ESIP:9200/_license/start_trial?acknowledge=true" >/dev/null 2>&1
  do
    sleep 2
  done

  
  echo ""
  echo "${green}[DEBUG]${reset} Stack is up but will take a minute or two to become healthy.  Please view ${blue}kubectl get pods${reset} to ensure that all pods are up before trying to login"

} # end helmstack

# FUNCTION - helmldap
helmldap() {
  
  echo ""
  echo "${green}[DEBUG]${reset} Adding OPENLDAP server with TLS and patching ES deployment for ldap realm"
  echo ""

  sleep 5
  echo "${green}[DEBUG]${reset} Creating override for ${1} deployment(starting with this since it will take the longest)"
  cat > ${WORKDIR}/es-override.yaml <<EOF
esConfig:
  elasticsearch.yml: |
    xpack.security.authc.realms.ldap.ldap1:
      order: 0
      url: "ldaps://openldap:1636"
      bind_dn: "cn=admin, dc=example, dc=org"
      user_search:
        base_dn: "dc=example,dc=org"
        filter: "(cn={0})"
      group_search:
        base_dn: "dc=example,dc=org"
      ssl:
        certificate_authorities: [ "config/openldap-certs/ca.crt" ]
        verification_mode: none
    xpack.security.enabled: true
    xpack.security.transport.ssl.enabled: true
    xpack.security.transport.ssl.verification_mode: certificate
    xpack.security.transport.ssl.certificate_authorities: /usr/share/elasticsearch/config/certs/ca.crt
    xpack.security.transport.ssl.certificate: /usr/share/elasticsearch/config/certs/${1}-es-default.crt
    xpack.security.transport.ssl.key: /usr/share/elasticsearch/config/certs/${1}-es-default.key
    xpack.security.http.ssl.enabled: true
    xpack.security.http.ssl.certificate_authorities: /usr/share/elasticsearch/config/certs/ca.crt
    xpack.security.http.ssl.certificate: /usr/share/elasticsearch/config/certs/${1}-es-default.crt
    xpack.security.http.ssl.key: /usr/share/elasticsearch/config/certs/${1}-es-default.key

keystore:
  - secretName: ldapbindpw-secret

#extraEnvs:
#  - name: ELASTIC_PASSWORD
#    valueFrom:
#      secretKeyRef:
#        name: elastic-credentials
#        key: password


secretMounts:
  - name: elastic-certificates
    secretName: elastic-certificates
    path: /usr/share/elasticsearch/config/certs
  - name: openldap-certificates
    secretName: openldap-certificates
    path: /usr/share/elasticsearch/config/openldap-certs
    defaultMode: 0644
EOF
  echo "${green}[DEBUG]${reset} Applying override to ${1}."
  helm upgrade elasticsearch elastic/elasticsearch -f ${WORKDIR}/es-values.yaml -f ${WORKDIR}/es-override.yaml --set imageTag=${VERSION} >/dev/null 2>&1
  sleep 2

  echo "${green}[DEBUG]${reset} Creating ldapbindpw secret to make the keystore entry for bindpw"
  cat > ${WORKDIR}/ldapbindpw-secret.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: ldapbindpw-secret
type: Opaque
data:
  xpack.security.authc.realms.ldap.ldap1.secure_bind_password: YWRtaW5wYXNzd29yZA==
EOF
  kubectl apply -f ${WORKDIR}/ldapbindpw-secret.yaml >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating ca.crt and server certificate/key for openldap"
  createcerts openldap openldap-certificates

  echo "${green}[DEBUG]${reset} Creating secret for users and passwords"
  kubectl create secret generic openldap --from-literal=adminpassword=adminpassword --from-literal=users=user01,user02 --from-literal=passwords=password01,password02 >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating openldap.yaml"
  cat > ${WORKDIR}/openldap.yaml<<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openldap
  labels:
    app.kubernetes.io/name: openldap
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: openldap
  replicas: 1
  template:
    metadata:
      labels:
        app.kubernetes.io/name: openldap
    spec:
      containers:
        - name: openldap
          image: docker.io/bitnami/openldap:latest
          imagePullPolicy: "Always"
          env:
            - name: LDAP_ADMIN_USERNAME
              value: "admin"
            - name: LDAP_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  key: adminpassword
                  name: openldap
            - name: LDAP_USERS
              valueFrom:
                secretKeyRef:
                  key: users
                  name: openldap
            - name: LDAP_PASSWORDS
              valueFrom:
                secretKeyRef:
                  key: passwords
                  name: openldap
            - name: LDAPTLS_REQCERT
              value: "never"
            - name: LDAP_ENABLE_TLS
              value: "yes"
            - name: LDAP_TLS_CA_FILE
              value: "/opt/bitnami/openldap/certs/ca.crt"
            - name: LDAP_TLS_CERT_FILE
              value: "/opt/bitnami/openldap/certs/openldap.crt"
            - name: LDAP_TLS_KEY_FILE
              value: "/opt/bitnami/openldap/certs/openldap.key"
          volumeMounts:
            - name: openldap-certificates
              mountPath: /opt/bitnami/openldap/certs
              readOnly: true
          ports:
            - name: tcp-ldap
              containerPort: 1636
      volumes:
        - name: openldap-certificates
          secret:
            secretName: openldap-certificates
            defaultMode: 0660

---
apiVersion: v1
kind: Service
metadata:
  name: openldap
  labels:
    app.kubernetes.io/name: openldap
spec:
  type: ClusterIP
  ports:
    - name: tcp-ldap
      port: 1636
      targetPort: tcp-ldap
  selector:
    app.kubernetes.io/name: openldap
EOF

  echo "${green}[DEBUG]${reset} Creating openldap server"
  kubectl apply -f ${WORKDIR}/openldap.yaml >/dev/null 2>&1

  sleep 5

  echo "${green}[DEBUG]${reset} Creating role mappings"
  until curl -k -u "elastic:${PASSWORD}" -XPUT "https://${ESIP}:9200/_security/role_mapping/ldap-admin" -H 'Content-Type: application/json' -d'
{"enabled":true,"roles":["superuser"],"rules":{"all":[{"field":{"realm.name":"ldap1"}}]},"metadata":{}}' >/dev/null 2>&1
  do
    sleep 2
  done

  echo "${green}[DEBUG]${red} Patching elasticsearch takes a while so please ensure that all ES pods have been recreated before trying to login with ldap${reset}"

} # end helmldap

# FUNCTION - helmbeats
helmbeats()
{

  echo "${green}[DEBUG]${reset} Deploying filebeat via helm"

  beatsetup "filebeat"
  beatsetup "metricbeat"
  
  echo "${green}[DEBUG]${reset} Creating fb-values.yaml"
  cat > ${WORKDIR}/fb-values.yaml <<EOF
---
daemonset:
  filebeatConfig:
    filebeat.yml: | 
      filebeat.inputs:
      - type: container
        paths:
          - /var/log/containers/*.log
        processors:
        - add_kubernetes_metadata:
            host: \${NODE_NAME}
            matchers:
            - logs_path:
                logs_path: "/var/log/containers/"

      filebeat.autodiscover:
        providers:
          - type: kubernetes
            node: \${NODE_NAME}
            hints.enabled: true
            hints.default_config:
              type: container
              paths:
                - /var/log/containers/*\${data.kubernetes.container.id}.log

      processors:
        - add_cloud_metadata:
        - add_host_metadata:

      logging.json: true
      output.elasticsearch:
        hosts: ["${1}-es-default:9200"]
        username: '\${ELASTICSEARCH_USERNAME}'
        password: '\${ELASTICSEARCH_PASSWORD}'
        protocol: https
        ssl.certificate_authorities:
          - /usr/share/filebeat/config/certs/ca.crt
  secretMounts:
    - name: elastic-certificates
      secretName: elastic-certificates
      path: /usr/share/filebeat/config/certs

  extraEnvs:
    - name: 'ELASTICSEARCH_USERNAME'
      valueFrom:
        secretKeyRef:
          name: elastic-credentials
          key: username
    - name: 'ELASTICSEARCH_PASSWORD'
      valueFrom:
        secretKeyRef:
          name: elastic-credentials
          key: password
  podAnnotations:
    co.elastic.logs.json-logging/json.keys_under_root: "true"
    co.elastic.logs.json-logging/json.add_error_key: "true"
    co.elastic.logs.json-logging/json.message_key: "message"
EOF
  
  echo "${green}[DEBUG]${reset} Deploying filebeat"
  helm install ${1}-fb elastic/filebeat -f ${WORKDIR}/fb-values.yaml --set imageTag=${VERSION} >/dev/null 2>&1

  checkhealth "daemonset" "${1}-fb-filebeat" "numberReady" "3"

  echo ""
  echo "${green}[DEBUG]${reset} Deploying metricbeat via helm"

  echo "${green}[DEBUG]${reset} Adding ${blue}prometheus-community${reset} repository as pre-req"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1
  helm repo update >/dev/null 2>&1
  
  echo "${green}[DEBUG]${reset} Create kube_state_metrics"
  helm install kube-state-metrics prometheus-community/kube-state-metrics >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating mb-values.yaml"
  cat > ${WORKDIR}/mb-values.yaml <<EOF
---
daemonset:
  # Allows you to add any config files in /usr/share/metricbeat
  # such as metricbeat.yml for daemonset
  metricbeatConfig:
    metricbeat.yml: |
      metricbeat.modules:
      - module: kubernetes
        metricsets:
          - container
          - node
          - pod
          - system
          - volume
        period: 10s
        host: "\${NODE_NAME}"
        hosts: ["https://\${NODE_NAME}:10250"]
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        ssl.verification_mode: "none"
        processors:
        - add_kubernetes_metadata: ~
      - module: kubernetes
        enabled: true
        metricsets:
          - event
      - module: system
        period: 10s
        metricsets:
          - cpu
          - load
          - memory
          - network
          - process
          - process_summary
        processes: ['.*']
        process.include_top_n:
          by_cpu: 5
          by_memory: 5
      - module: system
        period: 1m
        metricsets:
          - filesystem
          - fsstat
        processors:
        - drop_event.when.regexp:
            system.filesystem.mount_point: '^/(sys|cgroup|proc|dev|etc|host|lib)($|/)'
      output.elasticsearch:
        username: '\${ELASTICSEARCH_USERNAME}'
        password: '\${ELASTICSEARCH_PASSWORD}'
        protocol: https
        hosts: ["${1}-es-default:9200"]
        ssl.certificate_authorities:
          - /usr/share/metricbeat/config/certs/ca.crt
  secretMounts:
    - name: elastic-certificates
      secretName: elastic-certificates
      path: /usr/share/metricbeat/config/certs

  extraEnvs:
    - name: 'ELASTICSEARCH_USERNAME'
      valueFrom:
        secretKeyRef:
          name: elastic-credentials
          key: username
    - name: 'ELASTICSEARCH_PASSWORD'
      valueFrom:
        secretKeyRef:
          name: elastic-credentials
          key: password

deployment:
  # Allows you to add any config files in /usr/share/metricbeat
  # such as metricbeat.yml for deployment
  metricbeatConfig:
    metricbeat.yml: |
      metricbeat.modules:
      - module: kubernetes
        enabled: true
        metricsets:
          - state_node
          - state_deployment
          - state_replicaset
          - state_pod
          - state_container
        period: 10s
        hosts: ["\${KUBE_STATE_METRICS_HOSTS}"]
      output.elasticsearch:
        username: '\${ELASTICSEARCH_USERNAME}'
        password: '\${ELASTICSEARCH_PASSWORD}'
        protocol: https
        hosts: ["${1}-es-default:9200"]
        ssl.certificate_authorities:
          - /usr/share/metricbeat/config/certs/ca.crt
  secretMounts:
    - name: elastic-certificates
      secretName: elastic-certificates
      path: /usr/share/metricbeat/config/certs

  extraEnvs:
    - name: 'ELASTICSEARCH_USERNAME'
      valueFrom:
        secretKeyRef:
          name: elastic-credentials
          key: username
    - name: 'ELASTICSEARCH_PASSWORD'
      valueFrom:
        secretKeyRef:
          name: elastic-credentials
          key: password
EOF
  
  echo "${green}[DEBUG]${reset} Deploying metricbeat"
  helm install ${1}-mb elastic/metricbeat -f ${WORKDIR}/mb-values.yaml --set imageTag=${VERSION} >/dev/null 2>&1

  checkhealth "daemonset" "${1}-mb-metricbeat" "numberReady" "3"

} # end helmbeats

# FUNCTION - helmlogstash
helmlogstash() {

  echo "${green}[DEBUG]${reset} Deploying logstash via helm"
  
  echo "${green}[DEBUG]${reset} Creating ls-values.yaml"
  cat > ${WORKDIR}/ls-values.yaml <<EOF
---
persistence:
  enabled: true

logstashConfig:
  logstash.yml: |
    http.host: 0.0.0.0

logstashPipeline:
  logstash.conf: |
    input { beats { port => 5044 } }
    output { elasticsearch {
      hosts => ["https://${1}-es-default:9200"]
      cacert => "/usr/share/logstash/config/certs/ca.crt"
      user => '\${ELASTICSEARCH_USERNAME}'
      password => '\${ELASTICSEARCH_PASSWORD}'
      index => "%{[@metadata][beat]}-%{[@metadata][version]}"
      }
    }

secretMounts:
  - name: elastic-certificates
    secretName: elastic-certificates
    path: /usr/share/logstash/config/certs

extraEnvs:
  - name: 'ELASTICSEARCH_USERNAME'
    valueFrom:
      secretKeyRef:
        name: elastic-credentials
        key: username
  - name: 'ELASTICSEARCH_PASSWORD'
    valueFrom:
      secretKeyRef:
        name: elastic-credentials
        key: password

service:
  type: ClusterIP
  loadBalancerIP: ""
  ports:
    - name: beats
      port: 5044
      protocol: TCP
      targetPort: 5044
EOF

  echo "${green}[DEBUG]${reset} Deploying logstash"
  helm install ${1}-ls elastic/logstash -f ${WORKDIR}/ls-values.yaml --set imageTag=${VERSION} >/dev/null 2>&1

  checkhealth "statefulset" "${1}-ls-logstash" "readyReplicas" "1"

} # end helmlogstash

# FUNCTION - helmlsbeats
helmlsbeats() {

  beatsetup "filebeat"
  beatsetup "metricbeat"

  echo ""
  echo "${green}[DEBUG]${reset} Deploying filebeat via helm for logstash output"
  
  echo "${green}[DEBUG]${reset} Creating fb-values.yaml"
  cat > ${WORKDIR}/fb-values.yaml <<EOF
---
daemonset:
  filebeatConfig:
    filebeat.yml: |
      filebeat.inputs:
      - type: container
        paths:
          - /var/log/containers/*.log
        processors:
        - add_kubernetes_metadata:
            host: \${NODE_NAME}
            matchers:
            - logs_path:
                logs_path: "/var/log/containers/"
      output.logstash:
        hosts: ["${1}-ls-logstash:5044"]
  podAnnotations:
    co.elastic.logs.json-logging/json.keys_under_root: "true"
    co.elastic.logs.json-logging/json.add_error_key: "true"
    co.elastic.logs.json-logging/json.message_key: "message"
EOF
  
  echo "${green}[DEBUG]${reset} Deploying filebeat"
  helm install ${1}-fb elastic/filebeat -f ${WORKDIR}/fb-values.yaml --set imageTag=${VERSION} >/dev/null 2>&1

  checkhealth "daemonset" "${1}-fb-filebeat" "numberReady" "3"

  echo ""
  echo "${green}[DEBUG]${reset} Deploying metricbeat via helm"

  echo "${green}[DEBUG]${reset} Adding ${blue}prometheus-community${reset} repository as pre-req"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1
  helm repo update >/dev/null 2>&1
  
  echo "${green}[DEBUG]${reset} Create kube_state_metrics"
  helm install kube-state-metrics prometheus-community/kube-state-metrics >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating mb-values.yaml"
  cat > ${WORKDIR}/mb-values.yaml <<EOF
---
daemonset:
  # Allows you to add any config files in /usr/share/metricbeat
  # such as metricbeat.yml for daemonset
  metricbeatConfig:
    metricbeat.yml: |
      metricbeat.modules:
      - module: kubernetes
        metricsets:
          - container
          - node
          - pod
          - system
          - volume
        period: 10s
        host: "\${NODE_NAME}"
        hosts: ["https://\${NODE_NAME}:10250"]
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        ssl.verification_mode: "none"
        processors:
        - add_kubernetes_metadata: ~
      - module: kubernetes
        enabled: true
        metricsets:
          - event
      - module: system
        period: 10s
        metricsets:
          - cpu
          - load
          - memory
          - network
          - process
          - process_summary
        processes: ['.*']
        process.include_top_n:
          by_cpu: 5
          by_memory: 5
      - module: system
        period: 1m
        metricsets:
          - filesystem
          - fsstat
        processors:
        - drop_event.when.regexp:
            system.filesystem.mount_point: '^/(sys|cgroup|proc|dev|etc|host|lib)($|/)'
      output.logstash:
        hosts: ["${1}-ls-logstash:5044"]

deployment:
  # Allows you to add any config files in /usr/share/metricbeat
  # such as metricbeat.yml for deployment
  metricbeatConfig:
    metricbeat.yml: |
      metricbeat.modules:
      - module: kubernetes
        enabled: true
        metricsets:
          - state_node
          - state_deployment
          - state_replicaset
          - state_pod
          - state_container
        period: 10s
        hosts: ["\${KUBE_STATE_METRICS_HOSTS}"]
      output.logstash:
        hosts: ["${1}-ls-logstash:5044"]
EOF
  
  echo "${green}[DEBUG]${reset} Deploying metricbeat"
  helm install ${1}-mb elastic/metricbeat -f ${WORKDIR}/mb-values.yaml --set imageTag=${VERSION} >/dev/null 2>&1

  checkhealth "daemonset" "${1}-mb-metricbeat" "numberReady" "3"

} # end helmlsbeats

# FUNCTION - helmmonitor
helmmonitor() {
  
  echo ""
  echo "${green}[DEBUG]${reset} Deploying metricbeat via helm for stack monitoring"

  echo "${green}[DEBUG]${reset} Configuring elasticsearch"
  until curl --silent  -k -u "elastic:${PASSWORD}" -X PUT "https://${ESIP}:9200/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "xpack.monitoring.collection.enabled": true,
    "xpack.monitoring.elasticsearch.collection.enabled": false
  }
}
' > /dev/null 2>&1
  do
    sleep 2
  done

  echo "${green}[DEBUG]${reset} Creating mb-values.yaml"
  cat > ${WORKDIR}/mb-values.yaml <<EOF
---
daemonset:
  enabled: false

deployment:
  # Allows you to add any config files in /usr/share/metricbeat
  # such as metricbeat.yml for deployment
  metricbeatConfig:
    metricbeat.yml: |
      metricbeat.modules:
      - module: elasticsearch
        xpack.enabled: true
        period: 10s
        hosts: ["https://${1}-es-default:9200"] 
        scope: cluster 
        username: '\${ELASTICSEARCH_USERNAME}'
        password: '\${ELASTICSEARCH_PASSWORD}'
        ssl.enabled: true
        ssl.certificate_authorities:
          - /usr/share/metricbeat/config/certs/ca.crt
        ssl.verification_mode: "none"
      output.elasticsearch:
        username: '\${ELASTICSEARCH_USERNAME}'
        password: '\${ELASTICSEARCH_PASSWORD}'
        protocol: https
        hosts: ["${1}-es-default:9200"]
        ssl.certificate_authorities:
          - /usr/share/metricbeat/config/certs/ca.crt
  secretMounts:
    - name: elastic-certificates
      secretName: elastic-certificates
      path: /usr/share/metricbeat/config/certs

  extraEnvs:
    - name: 'ELASTICSEARCH_USERNAME'
      valueFrom:
        secretKeyRef:
          name: elastic-credentials
          key: username
    - name: 'ELASTICSEARCH_PASSWORD'
      valueFrom:
        secretKeyRef:
          name: elastic-credentials
          key: password
EOF

  sleep 5
  echo "${green}[DEBUG]${reset} Deploying metricbeat"
  helm install ${1}-mb elastic/metricbeat -f ${WORKDIR}/mb-values.yaml --set imageTag=${VERSION} >/dev/null 2>&1

  checkhealth "deployment" "${1}-mb-metricbeat-metrics" "readyReplicas" "1"

} # end helmmonitor

# FUNCTION - nativestack
nativestack()
{
  touch ${WORKDIR}/NATIVE

  echo ""
  echo "${green} ********** Deploying ELASTIC STACK ${blue}${VERSION}${green} Natively without helm or operator **************${reset}"
  echo ""

  # Create elastic users password and create secret
  echo "${green}[DEBUG]${reset} Create elastic user password and create a secret"
  PASSWORD=`openssl rand -base64 29 | tr -d "=+/" | cut -c1-25`
  kubectl create secret generic elastic-credentials --from-literal=password=$(echo $PASSWORD) --from-literal=username=elastic >/dev/null 2>&1

  # Create certificates
  echo "${green}[DEBUG]${reset} Create certificates for the stack and add create secrets"
  createcerts ${1}-es-default elastic-certificates
  createcerts ${1}-kb-default kibana-certificates

  # Create elasticsearch.yaml
  echo "${green}[DEBUG]${reset} Create elasticsearch.yaml"
  cat > ${WORKDIR}/elasticsearch.yaml <<EOF
---
# Source: elasticsearch/templates/poddisruptionbudget.yaml
apiVersion: policy/v1beta1
kind: PodDisruptionBudget
metadata:
  name: "${1}-default-pdb"
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: "${1}-default"
---
# Source: elasticsearch/templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${1}-default-config
  labels:
    app: "${1}-default"
data:
  elasticsearch.yml: |
    xpack.security.enabled: true
    xpack.security.transport.ssl.enabled: true
    xpack.security.transport.ssl.verification_mode: certificate
    xpack.security.transport.ssl.certificate_authorities: /usr/share/elasticsearch/config/certs/ca.crt
    xpack.security.transport.ssl.certificate: /usr/share/elasticsearch/config/certs/${1}-es-default.crt
    xpack.security.transport.ssl.key: /usr/share/elasticsearch/config/certs/${1}-es-default.key
    xpack.security.http.ssl.enabled: true
    xpack.security.http.ssl.certificate_authorities: /usr/share/elasticsearch/config/certs/ca.crt
    xpack.security.http.ssl.certificate: /usr/share/elasticsearch/config/certs/${1}-es-default.crt
    xpack.security.http.ssl.key: /usr/share/elasticsearch/config/certs/${1}-es-default.key
---
# Source: elasticsearch/templates/service.yaml
kind: Service
apiVersion: v1
metadata:
  name: ${1}-default
  labels:
    app: "${1}-default"
spec:
  type: LoadBalancer
  selector:
    app: "${1}-default"
  publishNotReadyAddresses: false
  ports:
  - name: http
    protocol: TCP
    port: 9200
  - name: transport
    protocol: TCP
    port: 9300
---
# Source: elasticsearch/templates/service.yaml
kind: Service
apiVersion: v1
metadata:
  name: ${1}-default-headless
  labels:
    app: "${1}-default"
  annotations:
    service.alpha.kubernetes.io/tolerate-unready-endpoints: "true"
spec:
  clusterIP: None # This is needed for statefulset hostnames like elasticsearch-0 to resolve
  # Create endpoints also if the related pod isn't ready
  publishNotReadyAddresses: true
  selector:
    app: "${1}-default"
  ports:
  - name: http
    port: 9200
  - name: transport
    port: 9300
---
# Source: elasticsearch/templates/statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ${1}-default
  labels:
    app: "${1}-default"
#  annotations:
#    esMajorVersion: "7"
spec:
  serviceName: ${1}-default-headless
  selector:
    matchLabels:
      app: "${1}-default"
  replicas: 3
  podManagementPolicy: Parallel
  updateStrategy:
    type: RollingUpdate
  volumeClaimTemplates:
  - metadata:
      name: ${1}-default
    spec:
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 2Gi
  template:
    metadata:
      name: "${1}-default"
      labels:
        app: "${1}-default"
      annotations:
        co.elastic.logs.json-logging/json.add_error_key: "true"
        co.elastic.logs.json-logging/json.keys_under_root: "true"
        co.elastic.logs.json-logging/json.message_key: "message"
        
#        configchecksum: b95db6488e46ed1fdea8a0b618610ee76ada610b7762775190aeb79ac2b0cf8
    spec:
      securityContext:
        fsGroup: 1000
        runAsUser: 1000
      automountServiceAccountToken: true
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - "${1}-default"
            topologyKey: kubernetes.io/hostname
      terminationGracePeriodSeconds: 120
      volumes:
        - name: elastic-certificates
          secret:
            secretName: elastic-certificates
        - name: esconfig
          configMap:
            name: ${1}-default-config
      enableServiceLinks: true
      initContainers:
      - name: configure-sysctl
        securityContext:
          runAsUser: 0
          privileged: true
        image: "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
        imagePullPolicy: "IfNotPresent"
        command: ["sysctl", "-w", "vm.max_map_count=262144"]
        resources:
          {}

      containers:
      - name: "elasticsearch"
        securityContext:
          capabilities:
            drop:
            - ALL
          runAsNonRoot: true
          runAsUser: 1000
        image: "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
        imagePullPolicy: "IfNotPresent"
        readinessProbe:
          exec:
            command:
              - bash
              - -c
              - |
                set -e
                # If the node is starting up wait for the cluster to be ready (request params: "wait_for_status=green&timeout=1s" )
                # Once it has started only check that the node itself is responding
                START_FILE=/tmp/.es_start_file

                # Disable nss cache to avoid filling dentry cache when calling curl
                # This is required with Elasticsearch Docker using nss < 3.52
                export NSS_SDB_USE_CACHE=no

                http () {
                  local path="\${1}"
                  local args="\${2}"
                  set -- -XGET -s

                  if [ "\$args" != "" ]; then
                    set -- "\$@" \$args
                  fi

                  if [ -n "\${ELASTIC_PASSWORD}" ]; then
                    set -- "\$@" -u "elastic:\${ELASTIC_PASSWORD}"
                  fi

                  curl --output /dev/null -k "\$@" "https://127.0.0.1:9200\${path}"
                }

                if [ -f "\${START_FILE}" ]; then
                  echo 'Elasticsearch is already running, lets check the node is healthy'
                  HTTP_CODE=\$(http "/" "-w %{http_code}")
                  RC=\$?
                  if [[ \${RC} -ne 0 ]]; then
                    echo "curl --output /dev/null -k -XGET -s -w '%{http_code}' \${BASIC_AUTH} https://127.0.0.1:9200/ failed with RC \${RC}"
                    exit \${RC}
                  fi
                  # ready if HTTP code 200, 503 is tolerable if ES version is 6.x
                  if [[ \${HTTP_CODE} == "200" ]]; then
                    exit 0
                  elif [[ \${HTTP_CODE} == "503" && "7" == "6" ]]; then
                    exit 0
                  else
                    echo "curl --output /dev/null -k -XGET -s -w '%{http_code}' \${BASIC_AUTH} https://127.0.0.1:9200/ failed with HTTP code \${HTTP_CODE}"
                    exit 1
                  fi

                else
                  echo 'Waiting for elasticsearch cluster to become ready (request params: "wait_for_status=green&timeout=1s" )'
                  if http "/_cluster/health?wait_for_status=green&timeout=1s" "--fail" ; then
                    touch \${START_FILE}
                    exit 0
                  else
                    echo 'Cluster is not yet ready (request params: "wait_for_status=green&timeout=1s" )'
                    exit 1
                  fi
                fi
          failureThreshold: 3
          initialDelaySeconds: 10
          periodSeconds: 10
          successThreshold: 3
          timeoutSeconds: 5
        ports:
        - name: http
          containerPort: 9200
        - name: transport
          containerPort: 9300
        resources:
          limits:
            cpu: 1000m
            memory: 2Gi
          requests:
            cpu: 1000m
            memory: 2Gi
        env:
          - name: node.name
            valueFrom:
              fieldRef:
                fieldPath: metadata.name
          - name: cluster.initial_master_nodes
            value: "${1}-default-0,${1}-default-1,${1}-default-2,"
          - name: discovery.seed_hosts
            value: "${1}-default-headless"
          - name: cluster.name
            value: "${1}"
          - name: network.host
            value: "0.0.0.0"
#          - name: cluster.deprecation_indexing.enabled
#            value: "false"
EOF
  if [ $(checkversion ${VERSION}) -lt $(checkversion "8.0.0") ]; then
    cat >> ${WORKDIR}/elasticsearch.yaml <<EOF
          - name: node.data
            value: "true"
          - name: node.ingest
            value: "true"
          - name: node.master
            value: "true"
          - name: node.ml
            value: "true"
#          - name: node.remote_cluster_client
#            value: "true"
EOF
  elif [ $(checkversion ${VERSION}) -ge $(checkversion "8.0.0") ]; then
    cat >> ${WORKDIR}/elasticsearch.yaml <<EOF
          - name: node.roles
            value: "master,data,data_content,data_hot,data_warm,data_cold,ingest,ml,remote_cluster_client,transform,"
EOF
  fi
  cat >> ${WORKDIR}/elasticsearch.yaml <<EOF
          - name: ELASTIC_PASSWORD
            valueFrom:
              secretKeyRef:
                key: password
                name: elastic-credentials
        volumeMounts:
          - name: "${1}-default"
            mountPath: /usr/share/elasticsearch/data

          - name: elastic-certificates
            mountPath: /usr/share/elasticsearch/config/certs
          - name: esconfig
            mountPath: /usr/share/elasticsearch/config/elasticsearch.yml
            subPath: elasticsearch.yml
EOF

  echo "${green}[DEBUG]${reset} Starting elasticsearch"
  kubectl apply -f ${WORKDIR}/elasticsearch.yaml >/dev/null 2>&1

  checkhealth "statefulset" "${1}-default" "readyReplicas" "3"
  sleep 5
  echo ""
  
  # get ESIP
  unset ESIP
  while [ "${ESIP}" = "" -o "${ESIP}" = "<pending>" ]
  do
    ESIP=`kubectl get service | grep ${1}-default | grep -v headless | awk '{ print $4 }'`
    sleep 2
  done


  # apply trial license
  echo "${green}[DEBUG]${reset} Applying trial license."
  until curl -k --silent -u "elastic:${PASSWORD}" -XPOST "https://$ESIP:9200/_license/start_trial?acknowledge=true" >/dev/null 2>&1
  do
    sleep 2
  done

  # start kibana
  echo "${green}[DEBUG]${reset} Creating kibana/kibana_system user."
  # set kibana or kibana_system password
  if [ $(checkversion $VERSION) -lt $(checkversion "7.8.0") ]; then
    until curl -k -s -X POST -u "elastic:${PASSWORD}" "https://${ESIP}:9200/_security/user/kibana/_password" -H "Content-Type: application/json" -d "{\"password\": \"${PASSWORD}\"}" | grep -q "^{}"; do sleep 10; done;
    kubectl create secret generic kibana-credentials --from-literal=password=$(echo $PASSWORD) --from-literal=username=kibana >/dev/null 2>&1
  elif [ $(checkversion $VERSION) -gt $(checkversion "7.8.0") ]; then
    until curl -k -s -X POST -u "elastic:${PASSWORD}" "https://${ESIP}:9200/_security/user/kibana_system/_password" -H "Content-Type: application/json" -d "{\"password\": \"${PASSWORD}\"}" | grep -q "^{}"; do sleep 10; done;
    kubectl create secret generic kibana-credentials --from-literal=password=$(echo $PASSWORD) --from-literal=username=kibana_system >/dev/null 2>&1
  fi
  
  # create encryptionkey and its secret
  echo "${green}[DEBUG]${reset} Creating kibana encryption key secret"
  encryptionkey=`openssl rand -base64 29 | tr -d "=+/" | cut -c1-32`
  kubectl create secret generic kibana-encryptionkey --from-literal=encryptionkey=$(echo $encryptionkey) >/dev/null 2>&1

  # Create kibana.yaml
  echo "${green}[DEBUG]${reset} Create kibana.yaml"
  cat > ${WORKDIR}/kibana.yaml <<EOF
---
# Source: kibana/templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${1}-kibana-config
  labels:
    app: kibana
    release: "${1}"
data:
  kibana.yml: |
    server.ssl:
      enabled: true
      key: /usr/share/kibana/config/certs/${1}-kb-default.key
      certificate: /usr/share/kibana/config/certs/${1}-kb-default.crt
    xpack.security.encryptionKey: \${KIBANA_ENCRYPTION_KEY}
    xpack.reporting.encryptionKey: \${KIBANA_ENCRYPTION_KEY}
EOF
  if [ $(checkversion ${VERSION}) -ge $(checkversion "7.7.0") ]; then
    cat >> ${WORKDIR}/kibana.yaml <<EOF
    xpack.encryptedSavedObjects.encryptionKey: \${KIBANA_ENCRYPTION_KEY}
EOF
  fi
  cat >> ${WORKDIR}/kibana.yaml <<EOF
    elasticsearch.ssl:
      certificateAuthorities: /usr/share/kibana/config/certs/ca.crt
      verificationMode: none
---
# Source: kibana/templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: ${1}-kibana
  labels:
    app: kibana
    release: "${1}"
spec:
  type: LoadBalancer
  ports:
    - port: 5601
      protocol: TCP
      name: http
      targetPort: 5601
  selector:
    app: kibana
    release: "${1}"
---
# Source: kibana/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${1}-kibana
  labels:
    app: kibana
    release: "${1}"
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: kibana
      release: "${1}"
  template:
    metadata:
      labels:
        app: kibana
        release: "${1}"
      annotations:
        co.elastic.logs.json-logging/json.add_error_key: "true"
        co.elastic.logs.json-logging/json.keys_under_root: "true"
        co.elastic.logs.json-logging/json.message_key: "message"

#        configchecksum: ba651b08865c8a31e3de76df5391cf73cfe73f6309e0d2f91882aeba69a5e92
    spec:
      automountServiceAccountToken: true
      securityContext:
        fsGroup: 1000
      volumes:
        - name: kibana-certificates
          secret:
            secretName: kibana-certificates
        - name: kibanaconfig
          configMap:
            name: ${1}-kibana-config
      containers:
      - name: kibana
        securityContext:
          capabilities:
            drop:
            - ALL
          runAsNonRoot: true
          runAsUser: 1000
        image: "docker.elastic.co/kibana/kibana:${VERSION}"
        imagePullPolicy: "IfNotPresent"
        env:
          - name: ELASTICSEARCH_HOSTS
            value: "https://${1}-default:9200"
          - name: SERVER_HOST
            value: "0.0.0.0"
          - name: NODE_OPTIONS
            value: --max-old-space-size=1800
          - name: ELASTICSEARCH_USERNAME
            valueFrom:
              secretKeyRef:
                key: username
                name: kibana-credentials
          - name: ELASTICSEARCH_PASSWORD
            valueFrom:
              secretKeyRef:
                key: password
                name: kibana-credentials
          - name: KIBANA_ENCRYPTION_KEY
            valueFrom:
              secretKeyRef:
                key: encryptionkey
                name: kibana-encryptionkey
        readinessProbe:
          failureThreshold: 3
          initialDelaySeconds: 10
          periodSeconds: 10
          successThreshold: 3
          timeoutSeconds: 5
          exec:
            command:
              - bash
              - -c
              - |
                #!/usr/bin/env bash -e

                # Disable nss cache to avoid filling dentry cache when calling curl
                # This is required with Kibana Docker using nss < 3.52
                export NSS_SDB_USE_CACHE=no

                http () {
                    local path="\${1}"
                    set -- -XGET -s --fail -L

                    # if [ -n "elastic" ] && [ -n "\${ELASTICSEARCH_PASSWORD}" ]; then
                      set -- "\$@" -u "elastic:\${ELASTICSEARCH_PASSWORD}"
                    # fi

                    STATUS=\$(curl --output /dev/null --write-out "%{http_code}" -k "\$@" "https://localhost:5601\${path}")
                    if [[ "\${STATUS}" -eq 200 ]]; then
                      exit 0
                    fi

                    echo "Error: Got HTTP code \${STATUS} but expected a 200"
                    exit 1
                }

                http "/app/kibana"
        ports:
        - containerPort: 5601
        resources:
          limits:
            cpu: 1000m
            memory: 2Gi
          requests:
            cpu: 1000m
            memory: 2Gi
        volumeMounts:
          - name: kibana-certificates
            mountPath: /usr/share/kibana/config/certs
          - name: kibanaconfig
            mountPath: /usr/share/kibana/config/kibana.yml
            subPath: kibana.yml
EOF

  echo "${green}[DEBUG]${reset} Starting kibana"
  kubectl apply -f ${WORKDIR}/kibana.yaml >/dev/null 2>&1

  checkhealth "deployment" "${1}-kibana" "readyReplicas" "1"
  echo ""

  createsummary ${1}

  echo ""
  echo "${green}[DEBUG]${reset} Stack is up but will take a minute or two to become healthy.  Please view ${blue}kubectl get pods${reset} to ensure that all pods are up before trying to login"
  
} # end nativestack

# FUNCTION - nativebeats
nativebeats()
{

  beatsetup "filebeat"
  beatsetup "metricbeat"
  
  echo ""
  echo "${green}[DEBUG]${reset} Deploying filebeat via kubernetes"

  echo "${green}[DEBUG]${reset} Create beats_role"
  until curl -k -s -X POST -u "elastic:${PASSWORD}" "https://${ESIP}:9200/_security/role/beats_role" -H "Content-Type: application/json" -d '{"cluster":["monitor","manage_ilm","read_ilm"],"indices":[{"names":["*beat-*",".monitoring-beats-*"],"privileges":["manage","create_index","create_doc","read"],"field_security":{"grant":["*"]},"allow_restricted_indices":false}],"applications":[{"application":"kibana-.kibana","privileges":["all"],"resources":["*"]}],"run_as":[],"metadata":{},"transient_metadata":{"enabled":true}}' >/dev/null 2>&1
  do
    sleep 2
  done

  echo "${green}[DEBUG]${reset} Create beats_user"
  if [ $(checkversion "${VERSION}") -gt $(checkversion "7.6.0") ]; then
    until curl -k -s -X POST -u "elastic:${PASSWORD}" "https://${ESIP}:9200/_security/user/beats_user" -H "Content-Type: application/json" -d '{"username":"beats_user","roles":["beats_role","beats_admin","ingest_admin","monitoring_user","remote_monitoring_agent","remote_monitoring_collector","kibana_system","kibana_admin"],"full_name":"beats_user","email":null,"metadata":{},"enabled":true,"password":"${PASSWORD}"}' >/dev/null 2>&1
    do
      sleep 2
    done
  else
    until curl -k -s -X POST -u "elastic:${PASSWORD}" "https://${ESIP}:9200/_security/user/beats_user" -H "Content-Type: application/json" -d '{"username":"beats_user","roles":["beats_role","beats_admin","ingest_admin","monitoring_user","remote_monitoring_agent","remote_monitoring_collector","kibana_system","kibana_user"],"full_name":"beats_user","email":null,"metadata":{},"enabled":true,"password":"'${PASSWORD}'"}' >/dev/null 2>&1
    do
      sleep 2
    done
  fi

  echo "${green}[DEBUG]${reset} Create beats_user password"
  until curl -k -s -X POST -u "elastic:${PASSWORD}" "https://${ESIP}:9200/_security/user/beats_user/_password" -H "Content-Type: application/json" -d "{\"password\": \"${PASSWORD}\"}" | grep -q "^{}"; do sleep 10; done;
  kubectl create secret generic beats-credentials --from-literal=password=$(echo $PASSWORD) --from-literal=username=beats_user >/dev/null 2>&1  
  
  echo "${green}[DEBUG]${reset} Creating filebeat-kubernetes.yaml"
  cat > ${WORKDIR}/filebeat-kubernetes.yaml <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-config
  namespace: default
  labels:
    k8s-app: filebeat
data:
  filebeat.yml: |-
    filebeat.autodiscover:
      providers:
        - type: kubernetes
          node: \${NODE_NAME}
          hints.enabled: true
          hints.default_config:
            type: container
            paths:
              - /var/log/containers/*\${data.kubernetes.container.id}.log

    processors:
      - add_kubernetes_metadata:
      - add_cloud_metadata:
      - add_host_metadata:

    cloud.id: \${ELASTIC_CLOUD_ID}
    cloud.auth: \${ELASTIC_CLOUD_AUTH}

    output.elasticsearch:
      hosts: ['\${ELASTICSEARCH_HOST:elasticsearch}:\${ELASTICSEARCH_PORT:9200}']
      protocol: https
      username: \${ELASTICSEARCH_USERNAME}
      password: \${ELASTICSEARCH_PASSWORD}
      ssl.certificate_authorities:
        - /usr/share/filebeat/config/certs/ca.crt
      ssl.verification_mode: none
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: native-lab-fb
  namespace: default
  labels:
    k8s-app: filebeat
spec:
  selector:
    matchLabels:
      k8s-app: filebeat
  template:
    metadata:
      labels:
        k8s-app: filebeat
    spec:
      serviceAccountName: filebeat
      terminationGracePeriodSeconds: 30
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      initContainers:
      - name: cleanup-hostpath
        image: docker.elastic.co/beats/filebeat:${VERSION}
        command: [ "/bin/sh", "-c" ]
        args: [ "rm -rf /usr/share/filebeat/data/*" ]
        volumeMounts:
        - name: data
          mountPath: /usr/share/filebeat/data
        securityContext:
          runAsUser: 0
      containers:
      - name: filebeat
        image: docker.elastic.co/beats/filebeat:${VERSION}
        args: [
          "-c", "/etc/filebeat.yml",
          "-e",
        ]
        env:
        - name: ELASTICSEARCH_HOST
          value: ${1}-default
        - name: ELASTICSEARCH_PORT
          value: "9200"
        - name: ELASTICSEARCH_USERNAME
          valueFrom:
            secretKeyRef:
              name: beats-credentials
              key: username
        - name: ELASTICSEARCH_PASSWORD
          valueFrom:
            secretKeyRef:
              name: beats-credentials
              key: password
        - name: ELASTIC_CLOUD_ID
          value:
        - name: ELASTIC_CLOUD_AUTH
          value:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        securityContext:
          runAsUser: 0
          # If using Red Hat OpenShift uncomment this:
          #privileged: true
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 100m
            memory: 100Mi
        volumeMounts:
        - name: config
          mountPath: /etc/filebeat.yml
          readOnly: true
          subPath: filebeat.yml
        - name: data
          mountPath: /usr/share/filebeat/data
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: elastic-certificates
          mountPath: /usr/share/filebeat/config/certs
          readOnly: true
      volumes:
      - name: config
        configMap:
          defaultMode: 0640
          name: filebeat-config
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      - name: varlog
        hostPath:
          path: /var/log
      # data folder stores a registry of read status for all files, so we don't send everything again on a Filebeat pod restart
      - name: data
        hostPath:
          # When filebeat runs as non-root user, this directory needs to be writable by group (g+w).
          path: /var/lib/filebeat-data
          type: DirectoryOrCreate
      - name: elastic-certificates
        secret:
          secretName: elastic-certificates
          defaultMode: 420
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: filebeat
subjects:
- kind: ServiceAccount
  name: filebeat
  namespace: default
roleRef:
  kind: ClusterRole
  name: filebeat
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: filebeat
  namespace: default
subjects:
  - kind: ServiceAccount
    name: filebeat
    namespace: default
roleRef:
  kind: Role
  name: filebeat
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: filebeat-kubeadm-config
  namespace: default
subjects:
  - kind: ServiceAccount
    name: filebeat
    namespace: default
roleRef:
  kind: Role
  name: filebeat-kubeadm-config
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: filebeat
  labels:
    k8s-app: filebeat
rules:
- apiGroups: [""] # "" indicates the core API group
  resources:
  - namespaces
  - pods
  - nodes
  verbs:
  - get
  - watch
  - list
- apiGroups: ["apps"]
  resources:
    - replicasets
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: filebeat
  # should be the namespace where filebeat is running
  namespace: default
  labels:
    k8s-app: filebeat
rules:
  - apiGroups:
      - coordination.k8s.io
    resources:
      - leases
    verbs: ["get", "create", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: filebeat-kubeadm-config
  namespace: default
  labels:
    k8s-app: filebeat
rules:
  - apiGroups: [""]
    resources:
      - configmaps
    resourceNames:
      - kubeadm-config
    verbs: ["get"]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: filebeat
  namespace: default
  labels:
    k8s-app: filebeat
---
EOF
  
  echo "${green}[DEBUG]${reset} Deploying filebeat"
  kubectl apply -f ${WORKDIR}/filebeat-kubernetes.yaml

  checkhealth "daemonset" "${1}-fb" "numberReady" "3"

  echo ""
  echo "${green}[DEBUG]${reset} Deploying metricbeat via kubernetes"

  echo "${green}[DEBUG]${reset} Cloning and starting kube-state-metrics"
  git clone https://github.com/kubernetes/kube-state-metrics.git ${WORKDIR}/kube-state-metrics >/dev/null 2>&1
  find ${WORKDIR}/kube-state-metrics/examples/standard -type f -print0 | xargs -0 sed -i '' -e 's/kube-system/default/g' >/dev/null 2>&1
  kubectl apply -f ${WORKDIR}/kube-state-metrics/examples/standard

  echo "${green}[DEBUG]${reset} Creating metricbeat-kubernetes.yaml"
  cat > ${WORKDIR}/metricbeat-kubernetes.yaml <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: metricbeat-daemonset-config
  namespace: default
  labels:
    k8s-app: metricbeat
data:
  metricbeat.yml: |-
    metricbeat.config.modules:
      # Mounted `metricbeat-daemonset-modules` configmap:
      path: \${path.config}/modules.d/*.yml
      # Reload module configs as they change:
      reload.enabled: false

    metricbeat.autodiscover:
      providers:
        - type: kubernetes
          scope: cluster
          node: \${NODE_NAME}
          # In large Kubernetes clusters consider setting unique to false
          # to avoid using the leader election strategy and
          # instead run a dedicated Metricbeat instance using a Deployment in addition to the DaemonSet
          unique: true
          templates:
            - config:
                - module: kubernetes
                  hosts: ["kube-state-metrics:8080"]
                  period: 10s
                  add_metadata: true
                  metricsets:
                    - state_node
                    - state_deployment
                    - state_daemonset
                    - state_replicaset
                    - state_pod
                    - state_container
                    - state_job
                    - state_cronjob
                    - state_resourcequota
                    - state_statefulset
                    - state_service
                - module: kubernetes
                  metricsets:
                    - apiserver
                  hosts: ["https://\${KUBERNETES_SERVICE_HOST}:\${KUBERNETES_SERVICE_PORT}"]
                  bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
                  ssl.certificate_authorities:
                    - /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
                  period: 30s
                # Uncomment this to get k8s events:
                #- module: kubernetes
                #  metricsets:
                #    - event
        # To enable hints based autodiscover uncomment this:
        #- type: kubernetes
        #  node: \${NODE_NAME}
        #  hints.enabled: true

    processors:
      - add_cloud_metadata:

    cloud.id: \${ELASTIC_CLOUD_ID}
    cloud.auth: \${ELASTIC_CLOUD_AUTH}

    output.elasticsearch:
      hosts: ['\${ELASTICSEARCH_HOST:elasticsearch}:\${ELASTICSEARCH_PORT:9200}']
      protocol: https
      username: \${ELASTICSEARCH_USERNAME}
      password: \${ELASTICSEARCH_PASSWORD}
      ssl.certificate_authorities:
        - /usr/share/filebeat/config/certs/ca.crt
      ssl.verification_mode: none
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: metricbeat-daemonset-modules
  namespace: default
  labels:
    k8s-app: metricbeat
data:
  system.yml: |-
    - module: system
      period: 10s
      metricsets:
        - cpu
        - load
        - memory
        - network
        - process
        - process_summary
        #- core
        #- diskio
        #- socket
      processes: ['.*']
      process.include_top_n:
        by_cpu: 5      # include top 5 processes by CPU
        by_memory: 5   # include top 5 processes by memory

    - module: system
      period: 1m
      metricsets:
        - filesystem
        - fsstat
      processors:
      - drop_event.when.regexp:
          system.filesystem.mount_point: '^/(sys|cgroup|proc|dev|etc|host|lib|snap)($|/)'
  kubernetes.yml: |-
    - module: kubernetes
      metricsets:
        - node
        - system
        - pod
        - container
        - volume
      period: 10s
      host: \${NODE_NAME}
      hosts: ["https://\${NODE_NAME}:10250"]
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      ssl.verification_mode: "none"
      # If there is a CA bundle that contains the issuer of the certificate used in the Kubelet API,
      # remove ssl.verification_mode entry and use the CA, for instance:
      #ssl.certificate_authorities:
        #- /var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt
    # Currently `proxy` metricset is not supported on Openshift, comment out section
    - module: kubernetes
      metricsets:
        - proxy
      period: 10s
      host: \${NODE_NAME}
      hosts: ["localhost:10249"]
---
# Deploy a Metricbeat instance per node for node metrics retrieval
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ${1}-mb
  namespace: default
  labels:
    k8s-app: metricbeat
spec:
  selector:
    matchLabels:
      k8s-app: metricbeat
  template:
    metadata:
      labels:
        k8s-app: metricbeat
    spec:
      serviceAccountName: metricbeat
      terminationGracePeriodSeconds: 30
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      initContainers:
      - name: cleanup-hostpath
        image: docker.elastic.co/beats/metricbeat:${VERSION}
        command: [ "/bin/sh", "-c" ]
        args: [ "rm -rf /usr/share/metricbeat/data/*" ]
        volumeMounts:
        - name: data
          mountPath: /usr/share/metricbeat/data
        securityContext:
          runAsUser: 0
      containers:
      - name: metricbeat
        image: docker.elastic.co/beats/metricbeat:${VERSION}
        args: [
          "-c", "/etc/metricbeat.yml",
          "-e",
          "-system.hostfs=/hostfs",
        ]
        env:
        - name: ELASTICSEARCH_HOST
          value: ${1}-default
        - name: ELASTICSEARCH_PORT
          value: "9200"
        - name: ELASTICSEARCH_USERNAME
          valueFrom:
            secretKeyRef:
              name: beats-credentials
              key: username
        - name: ELASTICSEARCH_PASSWORD
          valueFrom:
            secretKeyRef:
              name: beats-credentials
              key: password
        - name: ELASTIC_CLOUD_ID
          value:
        - name: ELASTIC_CLOUD_AUTH
          value:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        securityContext:
          runAsUser: 0
          # If using Red Hat OpenShift uncomment this:
          #privileged: true
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 100m
            memory: 100Mi
        volumeMounts:
        - name: config
          mountPath: /etc/metricbeat.yml
          readOnly: true
          subPath: metricbeat.yml
        - name: data
          mountPath: /usr/share/metricbeat/data
        - name: modules
          mountPath: /usr/share/metricbeat/modules.d
          readOnly: true
        - name: proc
          mountPath: /hostfs/proc
          readOnly: true
        - name: cgroup
          mountPath: /hostfs/sys/fs/cgroup
          readOnly: true
        - name: elastic-certificates
          mountPath: /usr/share/filebeat/config/certs
          readOnly: true
      volumes:
      - name: proc
        hostPath:
          path: /proc
      - name: cgroup
        hostPath:
          path: /sys/fs/cgroup
      - name: config
        configMap:
          defaultMode: 0640
          name: metricbeat-daemonset-config
      - name: modules
        configMap:
          defaultMode: 0640
          name: metricbeat-daemonset-modules
      - name: data
        hostPath:
          # When metricbeat runs as non-root user, this directory needs to be writable by group (g+w)
          path: /var/lib/metricbeat-data
          type: DirectoryOrCreate
      - name: elastic-certificates
        secret:
          secretName: elastic-certificates
          defaultMode: 420
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: metricbeat
subjects:
- kind: ServiceAccount
  name: metricbeat
  namespace: default
roleRef:
  kind: ClusterRole
  name: metricbeat
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: metricbeat
  namespace: default
subjects:
  - kind: ServiceAccount
    name: metricbeat
    namespace: default
roleRef:
  kind: Role
  name: metricbeat
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: metricbeat-kubeadm-config
  namespace: default
subjects:
  - kind: ServiceAccount
    name: metricbeat
    namespace: default
roleRef:
  kind: Role
  name: metricbeat-kubeadm-config
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: metricbeat
  labels:
    k8s-app: metricbeat
rules:
- apiGroups: [""]
  resources:
  - nodes
  - namespaces
  - events
  - pods
  - services
  verbs: ["get", "list", "watch"]
# Enable this rule only if planing to use Kubernetes keystore
#- apiGroups: [""]
#  resources:
#  - secrets
#  verbs: ["get"]
- apiGroups: ["extensions"]
  resources:
  - replicasets
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources:
  - statefulsets
  - deployments
  - replicasets
  verbs: ["get", "list", "watch"]
- apiGroups: ["batch"]
  resources:
  - jobs
  verbs: ["get", "list", "watch"]
- apiGroups:
  - ""
  resources:
  - nodes/stats
  verbs:
  - get
- nonResourceURLs:
  - "/metrics"
  verbs:
  - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: metricbeat
  # should be the namespace where metricbeat is running
  namespace: default
  labels:
    k8s-app: metricbeat
rules:
  - apiGroups:
      - coordination.k8s.io
    resources:
      - leases
    verbs: ["get", "create", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: metricbeat-kubeadm-config
  namespace: default
  labels:
    k8s-app: metricbeat
rules:
  - apiGroups: [""]
    resources:
      - configmaps
    resourceNames:
      - kubeadm-config
    verbs: ["get"]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: metricbeat
  namespace: default
  labels:
    k8s-app: metricbeat
---
EOF
  
  echo "${green}[DEBUG]${reset} Deploying metricbeat"
  kubectl apply -f ${WORKDIR}/metricbeat-kubernetes.yaml >/dev/null 2>&1

  checkhealth "daemonset" "${1}-mb" "numberReady" "3"

} # end nativebeats

# FUNCTION - native monitor
nativemonitor()
{
  echo ""
  echo "${green}[DEBUG]${reset} Deploying metricbeat via kubernetes for stack monitoring"

  echo "${green}[DEBUG]${reset} Configuring elasticsearch"
  until curl --silent  -k -u "elastic:${PASSWORD}" -X PUT "https://${ESIP}:9200/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "xpack.monitoring.collection.enabled": true,
    "xpack.monitoring.elasticsearch.collection.enabled": false
  }
}
' > /dev/null 2>&1
  do
    sleep 2
  done

  echo "${green}[DEBUG]${reset} Create beats_role"
  until curl -k -s -X POST -u "elastic:${PASSWORD}" "https://${ESIP}:9200/_security/role/beats_role" -H "Content-Type: application/json" -d '{"cluster":["monitor","manage_ilm","read_ilm"],"indices":[{"names":["*beat-*",".monitoring-beats-*"],"privileges":["all","manage","create_index","create_doc","read"],"field_security":{"grant":["*"]},"allow_restricted_indices":false}],"applications":[{"application":"kibana-.kibana","privileges":["all"],"resources":["*"]}],"run_as":[],"metadata":{},"transient_metadata":{"enabled":true}}' >/dev/null 2>&1
  do
    sleep 2
  done

  echo "${green}[DEBUG]${reset} Create beats_user"
  if [ $(checkversion "${VERSION}") -gt $(checkversion "7.6.0") ]; then
    until curl -k -s -X POST -u "elastic:${PASSWORD}" "https://${ESIP}:9200/_security/user/beats_user" -H "Content-Type: application/json" -d '{"username":"beats_user","roles":["beats_role","beats_admin","ingest_admin","monitoring_user","remote_monitoring_agent","remote_monitoring_collector","kibana_system","kibana_admin"],"full_name":"beats_user","email":null,"metadata":{},"enabled":true,"password":"${PASSWORD}"}' >/dev/null 2>&1
    do
      sleep 2
    done
  else
    until curl -k -s -X POST -u "elastic:${PASSWORD}" "https://${ESIP}:9200/_security/user/beats_user" -H "Content-Type: application/json" -d '{"username":"beats_user","roles":["beats_role","beats_admin","ingest_admin","monitoring_user","remote_monitoring_agent","remote_monitoring_collector","kibana_system","kibana_user"],"full_name":"beats_user","email":null,"metadata":{},"enabled":true,"password":"'${PASSWORD}'"}' >/dev/null 2>&1
    do
      sleep 2
    done
  fi

  echo "${green}[DEBUG]${reset} Create beats_user password"
  until curl -k -s -X POST -u "elastic:${PASSWORD}" "https://${ESIP}:9200/_security/user/beats_user/_password" -H "Content-Type: application/json" -d "{\"password\": \"${PASSWORD}\"}" | grep -q "^{}"; do sleep 10; done;
  kubectl create secret generic beats-credentials --from-literal=password=$(echo $PASSWORD) --from-literal=username=beats_user >/dev/null 2>&1  

  echo "${green}[DEBUG]${reset}Creating metricbeat-kubernetes.yaml"
  cat > ${WORKDIR}/metricbeat-kubernetes.yaml <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: metricbeat-daemonset-config
  namespace: default
  labels:
    k8s-app: metricbeat
data:
  metricbeat.yml: |-
    metricbeat.modules:
    - module: elasticsearch
EOF

  es78="
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
"

  es74="
      metricsets:
      - ccr
      - cluster_stats
      - index
      - index_recovery
      - index_summary
      - ml_job
      - node_stats
      - shard
"

  if [ $(checkversion $VERSION) -ge $(checkversion "7.5.0") ] && [ $(checkversion $VERSION) -lt $(checkversion "7.9.0") ]; then
    echo "${es78}" >> ${WORKDIR}/metricbeat-kubernetes.yaml
  elif [ $(checkversion $VERSION) -lt $(checkversion "7.5.0") ]; then
    echo "${es74}" >> ${WORKDIR}/metricbeat-kubernetes.yaml
  fi

  cat >> ${WORKDIR}/metricbeat-kubernetes.yaml <<EOF
      xpack.enabled: true
      period: 10s
EOF
  if [ $(checkversion $VERSION) -lt $(checkversion "7.9.0") ]; then
    cat >> ${WORKDIR}/metricbeat-kubernetes.yaml <<EOF
      hosts: ["https://native-lab-default-0.native-lab-default-headless.default.svc.cluster.local:9200", "https://native-lab-default-1.native-lab-default-headless.default.svc.cluster.local:9200", "https://native-lab-default-2.native-lab-default-headless.default.svc.cluster.local:9200"]
EOF
  else
    cat >> ${WORKDIR}/metricbeat-kubernetes.yaml <<EOF
      hosts: ["https://\${ELASTICSEARCH_HOST}:9200"]
      scope: cluster
EOF
  fi
  cat >> ${WORKDIR}/metricbeat-kubernetes.yaml <<EOF
      username: '\${ELASTICSEARCH_USERNAME}'
      password: '\${ELASTICSEARCH_PASSWORD}'
      ssl.enabled: true
      ssl.certificate_authorities:
        - /usr/share/metricbeat/config/certs/ca.crt
      ssl.verification_mode: "none"
    processors:
      - add_cloud_metadata:

    cloud.id: \${ELASTIC_CLOUD_ID}
    cloud.auth: \${ELASTIC_CLOUD_AUTH}

    output.elasticsearch:
      hosts: ['\${ELASTICSEARCH_HOST:elasticsearch}:\${ELASTICSEARCH_PORT:9200}']
      protocol: https
      username: \${ELASTICSEARCH_USERNAME}
      password: \${ELASTICSEARCH_PASSWORD}
      ssl.certificate_authorities:
        - /usr/share/metricbeat/config/certs/ca.crt
      ssl.verification_mode: none
---
# Deploy a Metricbeat instance per node for node metrics retrieval
apiVersion: apps/v1
kind: Deployment
metadata:
  name: native-lab-mb
  namespace: default
  labels:
    k8s-app: metricbeat
spec:
  selector:
    matchLabels:
      k8s-app: metricbeat
  template:
    metadata:
      labels:
        k8s-app: metricbeat
    spec:
      serviceAccountName: metricbeat
      terminationGracePeriodSeconds: 30
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      initContainers:
      - name: cleanup-hostpath
        image: docker.elastic.co/beats/metricbeat:${VERSION}
        command: [ "/bin/sh", "-c" ]
        args: [ "rm -rf /usr/share/metricbeat/data/*" ]
        volumeMounts:
        - name: data
          mountPath: /usr/share/metricbeat/data
        securityContext:
          runAsUser: 0
      containers:
      - name: metricbeat
        image: docker.elastic.co/beats/metricbeat:${VERSION}
        args: [
          "-c", "/etc/metricbeat.yml",
          "-e",
          "-system.hostfs=/hostfs",
        ]
        env:
        - name: ELASTICSEARCH_HOST
          value: native-lab-default
        - name: ELASTICSEARCH_PORT
          value: "9200"
EOF
  if [ $(checkversion ${VERSION}) -lt $(checkversion "8.0.0") ]; then
    cat >> ${WORKDIR}/metricbeat-kubernetes.yaml <<EOF
        - name: ELASTICSEARCH_USERNAME
          valueFrom:
            secretKeyRef:
              name: beats-credentials
              key: username
        - name: ELASTICSEARCH_PASSWORD
          valueFrom:
            secretKeyRef:
              name: beats-credentials
              key: password
EOF
  else
    cat >> ${WORKDIR}/metricbeat-kubernetes.yaml <<EOF
        - name: ELASTICSEARCH_USERNAME
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: username
        - name: ELASTICSEARCH_PASSWORD
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: password
EOF
  fi
  cat >> ${WORKDIR}/metricbeat-kubernetes.yaml <<EOF
        - name: ELASTIC_CLOUD_ID
          value:
        - name: ELASTIC_CLOUD_AUTH
          value:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        securityContext:
          runAsUser: 0
          # If using Red Hat OpenShift uncomment this:
          #privileged: true
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 100m
            memory: 100Mi
        volumeMounts:
        - name: config
          mountPath: /etc/metricbeat.yml
          readOnly: true
          subPath: metricbeat.yml
        - name: data
          mountPath: /usr/share/metricbeat/data
          readOnly: false
        - name: proc
          mountPath: /hostfs/proc
          readOnly: true
        - name: cgroup
          mountPath: /hostfs/sys/fs/cgroup
          readOnly: true
        - name: elastic-certificates
          mountPath: /usr/share/metricbeat/config/certs
          readOnly: true
      volumes:
      - name: proc
        hostPath:
          path: /proc
      - name: cgroup
        hostPath:
          path: /sys/fs/cgroup
      - name: config
        configMap:
          defaultMode: 0640
          name: metricbeat-daemonset-config
      - name: data
        hostPath:
          # When metricbeat runs as non-root user, this directory needs to be writable by group (g+w)
          path: /var/lib/metricbeat-data
          type: DirectoryOrCreate
      - name: elastic-certificates
        secret:
          secretName: elastic-certificates
          defaultMode: 420
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: metricbeat
subjects:
- kind: ServiceAccount
  name: metricbeat
  namespace: default
roleRef:
  kind: ClusterRole
  name: metricbeat
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: metricbeat
  namespace: default
subjects:
  - kind: ServiceAccount
    name: metricbeat
    namespace: default
roleRef:
  kind: Role
  name: metricbeat
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: metricbeat-kubeadm-config
  namespace: default
subjects:
  - kind: ServiceAccount
    name: metricbeat
    namespace: default
roleRef:
  kind: Role
  name: metricbeat-kubeadm-config
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: metricbeat
  labels:
    k8s-app: metricbeat
rules:
- apiGroups: [""]
  resources:
  - nodes
  - namespaces
  - events
  - pods
  - services
  verbs: ["get", "list", "watch"]
# Enable this rule only if planing to use Kubernetes keystore
#- apiGroups: [""]
#  resources:
#  - secrets
#  verbs: ["get"]
- apiGroups: ["extensions"]
  resources:
  - replicasets
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources:
  - statefulsets
  - deployments
  - replicasets
  verbs: ["get", "list", "watch"]
- apiGroups: ["batch"]
  resources:
  - jobs
  verbs: ["get", "list", "watch"]
- apiGroups:
  - ""
  resources:
  - nodes/stats
  verbs:
  - get
- nonResourceURLs:
  - "/metrics"
  verbs:
  - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: metricbeat
  # should be the namespace where metricbeat is running
  namespace: default
  labels:
    k8s-app: metricbeat
rules:
  - apiGroups:
      - coordination.k8s.io
    resources:
      - leases
    verbs: ["get", "create", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: metricbeat-kubeadm-config
  namespace: default
  labels:
    k8s-app: metricbeat
rules:
  - apiGroups: [""]
    resources:
      - configmaps
    resourceNames:
      - kubeadm-config
    verbs: ["get"]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: metricbeat
  namespace: default
  labels:
    k8s-app: metricbeat
---
EOF
  
  echo "${green}[DEBUG]${reset} Deploying metricbeat"
  kubectl apply -f ${WORKDIR}/metricbeat-kubernetes.yaml >/dev/null 2>&1

  checkhealth "deployment" "native-lab-mb" "readyReplicas" "1"

} # end nativemonitor


#############################################################
# MAIN SCRIPT
#############################################################


case ${1} in
  operator)
    if [ -z ${2} ]; then
      help
      exit
    fi
    checkjq
    checkdocker
    checkkubectl
    checkopenssl
    ECKVERSION=${2}
    checkdir
    operator
    ;;
  build|start|stack|eck)
    if [ -z ${2} -o -z ${3} ]; then
      help
      exit
    fi
    checkjq
    checkdocker
    checkkubectl
    checkopenssl
    VERSION=${2}
    ECKVERSION=${3}
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    checkdir
    operator
    stackbuild "eck-lab"
    summary
    ;;
  eckldap)
    if [ -z ${2} -o -z ${3} ]; then
      help
      exit
    fi
    checkjq
    checkdocker
    checkkubectl
    checkopenssl
    VERSION=${2}
    ECKVERSION=${3}
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    checkdir
    operator
    stackbuild "eck-lab"
    eckldap
    summary
    ;;
  dedicated)
    if [ -z ${2} -o -z ${3} ]; then
      help
      exit
    fi
    checkjq
    checkdocker
    checkkubectl
    checkopenssl
    VERSION=${2}
    ECKVERSION=${3}
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    checkdir
    operator
    dedicated "eck-lab"
    summary
    ;;
  beats|beat)
    if [ -z ${2} -o -z ${3} ]; then
      help
      exit
    fi
    checkjq
    checkdocker
    checkkubectl
    checkopenssl
    VERSION=${2}
    ECKVERSION=${3}
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    checkdir
    operator
    stackbuild "eck-lab"
    beats "eck-lab"
    summary
    ;;
  monitor1)
    if [ -z ${2} -o -z ${3} ]; then
      help
      exit
    fi
    checkjq
    checkdocker
    checkkubectl
    checkopenssl
    VERSION=${2}
    ECKVERSION=${3}
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    checkdir
    operator
    stackbuild "eck-lab"
    stackbuild "eck-lab-monitor"
    monitor1 "eck-lab"
    summary
    ;;
  monitor2)
    if [ -z ${2} -o -z ${3} ]; then
      help
      exit
    fi
    checkjq
    checkdocker
    checkkubectl
    checkopenssl
    VERSION=${2}
    ECKVERSION=${3}
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    if [ $(checkversion $ECKVERSION) -lt $(checkversion "1.7.0") -o $(checkversion $VERSION) -lt $(checkversion "7.14.0") ]; then
      echo "${red}[DEBUG]${reset} Sidecar stack monitoring started with ECK 1.7.0 & STACK 7.14.0.  Please run cleanup and re-run wiht ECK operator 1.7.0+/Stack 7.14.0+"
      echo ""
      help
      exit
    else
      checkdir
      operator
      stackbuild "eck-lab-monitor"
      monitor2 "eck-lab"
      summary
    fi
    ;;
  fleet)
    if [ -z ${2} -o -z ${3} ]; then
      help
      exit
    fi
    VERSION=${2}
    ECKVERSION=${3}
    if [ $(checkversion $ECKVERSION) -lt $(checkversion "1.7.0") -o $(checkversion $VERSION) -lt $(checkversion "7.14.0") ]; then
      echo "${red}[DEBUG]${reset} Fleet server started with ECK 1.7.0 and STACK 7.14.0.  Please run cleanup and re-run with ECK operator 1.7.0+/Stack 7.14.0+"
      echo ""
      help
      exit
    else
      checkjq
      checkdocker
      checkkubectl
      checkopenssl
      checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
      checkrequiredversion
      checkdir
      operator
      stackbuild "eck-lab"
      fleet "eck-lab"
      summary
    fi
    ;;
  helm)
    if [ -z ${2} ]; then
      help
      exit
    fi
    checkjq
    checkdocker
    checkkubectl
    checkopenssl
    checkhelm
    VERSION=${2}
    checkrequiredversionhelm
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    helmstack "helm-lab"
    summary
    ;;
  helmldap)
    if [ -z ${2} ]; then
      help
      exit
    fi
    checkjq
    checkdocker
    checkkubectl
    checkopenssl
    checkhelm
    VERSION=${2}
    checkrequiredversionhelm
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    helmstack "helm-lab"
    helmldap "helm-lab"
    summary
    ;;
  helmbeats)
    if [ -z ${2} ]; then
      help
      exit
    fi
    checkjq
    checkdocker
    checkkubectl
    checkopenssl
    checkhelm
    VERSION=${2}
    checkrequiredversionhelm
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    helmstack "helm-lab"
    helmbeats "helm-lab"
    summary
    ;;
  helmlogstashbeats)
    if [ -z ${2} ]; then
      help
      exit
    fi
    checkjq
    checkdocker
    checkkubectl
    checkopenssl
    checkhelm
    VERSION=${2}
    checkrequiredversionhelm
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    helmstack "helm-lab"
    helmlogstash "helm-lab"
    helmlsbeats "helm-lab"
    summary
    ;;
  helmmonitor)
    if [ -z ${2} ]; then
      help
      exit
    fi
    checkjq
    checkdocker
    checkkubectl
    checkopenssl
    checkhelm
    VERSION=${2}
    checkrequiredversionhelm
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    helmstack "helm-lab"
    helmmonitor "helm-lab"
    summary
    ;;
  native)
    if [ -z ${2} ]; then
      help
      exit
    fi
    checkjq
    checkdocker
    checkkubectl
    checkopenssl
    VERSION=${2}
    checkrequiredversionnative "7.3.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    nativestack "native-lab"
    summary
    ;;
  nativebeats)
    if [ -z ${2} ]; then
      help
      exit
    fi
    checkjq
    checkdocker
    checkkubectl
    checkopenssl
    VERSION=${2}
    checkrequiredversionnative "7.3.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    nativestack "native-lab"
    nativebeats "native-lab"
    summary
    ;;
  nativemonitor)
    if [ -z ${2} ]; then
      help
      exit
    fi
    checkjq
    checkdocker
    checkkubectl
    checkopenssl
    VERSION=${2}
    checkrequiredversionnative "7.5.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    nativestack "native-lab"
    nativemonitor "native-lab"
    summary
    ;;
  cleanup|clean|teardown|stop)
    cleanup
    exit
    ;;
  info|summary|detail)
    summary
    ;;
  *)
    help
    exit
    ;;
esac
