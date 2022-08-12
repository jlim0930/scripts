#!/usr/bin/env bash

# justin lim <justin@isthecoolest.ninja>
# 
# version 1.0

# curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/deploy-eck.sh -o deploy-eck.sh
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


# set WORKDIR
WORKDIR="${HOME}/eckstack"

###############################################################################################################
# colors
red=`tput setaf 1`
green=`tput setaf 2`
blue=`tput setaf 4`
reset=`tput sgr0`

###############################################################################################################
# help
help() 
{
  echo ""
  echo "${green}This script is limited to ECK Operator 1.4.0+ & Stack 7.10.0+."
  echo "${green}  - various commands have additional limitations that will be listed below."
  echo ""
  echo "${green}USAGE:${reset} ./`basename $0` command STACKversion ECKversion"
  echo ""
  echo "${blue}COMMANDS:${reset}"
  echo "    ${green}operator${reset} - will just stand up the operator only and apply a trial license"
  echo "    ${green}stack|start|build${reset} - will stand up the ECK Operator, elasticsearch, & kibana with CLUSTER name : ${blue}eck-lab${reset}"
  echo "    ${green}beats${reset} - will stand up the basic stack + filebeat, metricbeat, packetbeat, & heartbeat"
  echo "    ${green}monitor1${reset} - will stand up the basic stack named ${blue}eck-lab${reset} and a monitoring stack named ${blue}eck-lab-monitor${reset}, filebeat, & metricbeat as PODS to report stack monitoring to ${blue}eck-lab-monitor${reset}"
  echo "    ${green}monitor2${reset} - will be the same as ${blue}monitor1${reset} however both filebeat & metricbeat will be a sidecar container inside of elasticsearch & kibana Pods. Limited to ECK ${blue}1.7.0+${reset} & STACK ${blue}7.14.0+${reset}"
  echo "    ${green}fleet${reset} - will stand up the basic stack + FLEET Server & elastic-agent as DaemonSet on each ECK node."
  echo ""
  echo "    ${green}cleanup${reset} - will delete all the resources including the ECK operator"
  echo ""
  echo "${green}EXAMPLE: ${reset}./`basename $0` fleet 8.2.0 2.2.0"
  echo ""
  echo "All yaml files will be stored in ${blue}~/eckstack${reset}"
  echo "    ${blue}~/eckstack/notes${reset} will contain all endpoint and password information"
  echo "    ${blue}~/eckstack/ca.crt${reset} will be the CA used to sign the public certificate"
  echo ""
} # end of help

###############################################################################################################
# functions

# cleanup function
cleanup()
{
  # make sure to name all yaml files as .yaml so that it can be picked up during cleanup
  echo ""
  echo "${green}********** Cleaning up **********${reset}"
  echo ""

  for item in `ls -1t ${WORKDIR}/*.yaml 2>/dev/null`
  do
    echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}${item}${reset}"
    kubectl delete -f ${item} > /dev/null 2>&1
  done

  rm -rf ${WORKDIR} > /dev/null 2>&1
  echo ""
  echo "${green}[DEBUG]${reset} All cleanedup"
  echo ""
} # end of cleanup function

createsummary()
{
  unset PASSWORD
  while [ "${PASSWORD}" = "" ]
  do
    PASSWORD=$(kubectl get secret ${1}-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')
    echo "${green}[DEBUG]${reset} Grabbing elastic password for ${1}: ${blue}${PASSWORD}${reset}"
  done
  echo "${1} elastic password: ${PASSWORD}" >> notes
  
  unset ESIP
  while [ "${ESIP}" = "" ]
  do
    ESIP=`kubectl get service | grep ${1}-es-http | awk '{ print $4 }'`
    echo "${green}[DEBUG]${reset} Grabbing elasticsearch endpoint for  ${1}: ${blue}https://${ESIP}:9200${reset}"
  done
  echo "${1} elasticsearch endpoint: https://${ESIP}:9200" >> notes
  
  unset KIBANAIP
  while [ "${KIBANAIP}" = "" -o "${KIBANAIP}" = "<pending>" ]
  do
    KIBANAIP=`kubectl get service | grep ${1}-kb-http | awk '{ print $4 }'`
    echo "${green}[DEBUG]${reset} Grabbing kibana endpoint for ${1}: ${blue}https://${KIBANAIP}:5601${reset}"
  done
  echo "${1} kibana endpoint: https://${KIBANAIP}:5601" >> notes

  if [ "${1}" = "eck-lab" ]; then
    kubectl get secrets ${1}-es-http-certs-public -o jsonpath="{.data.ca\.crt}" | base64 -d > ca.crt
  fi

  echo ""
}

summary()
{
  echo ""
  echo "${green}[SUMMARY]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset}"
  echo ""
  kubectl get all
  echo ""
  echo "${green}[SUMMARY]${reset} STACK INFO:"
  while read line
  do
    string1=`echo $line | awk -F": " '{ print $1 }'`
    string2=`echo $line | awk -F": " '{ print $2 }'`
    echo "${string1}: ${blue}${string2}${reset}"
  done < ${WORKDIR}/notes

  # cat ${WORKDIR}/notes

  #echo "${green}[SUMMARY]${reset} ${1} elastic user password: ${blue}`cat ${WORKDIR}/notes | grep 'ECK-LAB elastic password' | awk '{ print $NF }'`${reset}"
  #echo "${green}[SUMMARY]${reset} ${1} elasticsearch endpoint: ${blue}`cat ${WORKDIR}/notes | grep 'ECK-LAB elasticsearch endpoint' | awk '{ print $NF }'`${reset}"
  #echo "${green}[SUMMARY]${reset} ECK-LAB kibana endpoint: ${blue}`cat ${WORKDIR}/notes | grep 'ECK-LAB kibana endpoint' | awk '{ print $NF }'`${reset}"
  echo ""
  echo "${green}[SUMMARY]${reset} ${blue}ca.crt${reset} is located in ${blue}${WORKDIR}/ca.crt${reset}"
  #echo "${green}[SUMMARY]${reset} EXAMPLE: ${blue}curl --cacert ${WORKDIR}/ca.crt -u \"elastic:${PASSWORD}\" https://${ESIP}:9200${reset}"
  # curl --cacert ${WORKDIR}/ca.crt -u "elastic:${PASSWORD}" https://${ESIP}:9200
  echo ""
  echo "${green}[NOTE]${reset} If you missed the summary its also in ${blue}${WORKDIR}/notes${reset}"
  echo "${green}[NOTE]${reset} You can start logging into kibana but please give things few minutes for proper startup and letting components settle down."
  echo ""
}

# check jq
checkjq()
{
  if ! [ -x "$(command -v jq)" ]; then
    echo "${red}[DEBUG]${reset} jq is not installed.  Please install jq and try again"
    exit
  fi
} # end of checkjq

# check kubectl
checkkubectl()
{
  if [ `kubectl version 2>/dev/null | grep -c "Client Version"` -lt 1 ]; then
    echo "${red}[DEBUG]${reset} kubectl is not installed.  Please install kubectl and try again"
    exit
  fi
  if [ `kubectl version 2>/dev/null | grep -c "Server Version"` -lt 1 ]; then
    echo "${red}[DEBUG]${reset} kubectl is not connecting to any kubernetes environment"
    echo "${red}[DEBUG]${reset} if you did not setup your k8s environment.  Please configure your kubernetes environment and try again"
    exit
  fi
} # end checkubectl

# function used for version checking and comparing
checkversion() 
{
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
} # end of checkversion function

# check directory exist 
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
  echo ${VERSION} > VERSION
  echo ${ECKVERSION} > ECKVERSION

} # checkdir

# check health of various things
checkhealth() {
  sleep 3
  while true
  do
    if [ "`kubectl get ${1} | grep "${2} " | awk '{ print $2 }'`" = "green" ]; then
      sleep 2
      echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset}  STACK ${blue}${VERSION}${reset} is ${green}HEALTHY${reset}"
      echo ""
      kubectl get ${1}
      echo ""
      break
    else
      echo "${red}[DEBUG]${reset} ${1} is starting.  Checking again in 20 seconds.  If this does not finish in few minutes something is wrong. CTRL-C please"
      #echo ""
      #kubectl get ${1}
      #echo ""
      #kubectl get pods | grep "${2} "
      #echo ""
      sleep 20
    fi
  done
} # end checkhealth

###############################################################################################################
# operator
operator() 
{
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} OPERATOR **************${reset}"
  echo ""
  # all version checks complete & directory structures created starting operator
  if [ $(checkversion $ECKVERSION) -lt $(checkversion "1.7.0") ]; then # if version is less than 1.7.0
    echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} downloading operator: all-in-one.yaml"
    if curl -sL --fail https://download.elastic.co/downloads/eck/${ECKVERSION}/all-in-one.yaml -o all-in-one.yaml; then # if curl is successful
      kubectl apply -f all-in-one.yaml > /dev/null 2>&1
    else
      echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} Failed to get all-in-one.yaml - check network/version?"
      echo ""
      help
      exit
    fi
  else # if eckversion is not less than 1.7.0
    echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} downloading crds: crds.yaml"
    if curl -fsSL https://download.elastic.co/downloads/eck/${ECKVERSION}/crds.yaml -o crds.yaml; then
      kubectl create -f crds.yaml > /dev/null 2>&1
    else
      echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} Failed to get crds.yaml - check network/version?"
      echo ""
      help
      exit
    fi
    echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} downloading operator: operator.yaml"
    if curl -fsSL https://download.elastic.co/downloads/eck/${ECKVERSION}/operator.yaml -o operator.yaml; then
      kubectl create -f operator.yaml > /dev/null 2>&1
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
      sleep 2
      echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} OPERATOR is ${green}HEALTHY${reset}"
      echo ""
      kubectl -n elastic-system get all
      echo ""
      break
    else
      echo "${red}[DEBUG]${reset} ECK Operator is starting.  Checking again in 20 seconds.  If the operator does not goto Running status in few minutes something is wrong. CTRL-C please"
      # kubectl -n elastic-system get pod 
      echo ""
      sleep 20
    fi
  done
  
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} Creating license.yaml"
  # apply trial licence
  cat >>license.yaml<<EOF
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
  kubectl apply -f license.yaml  > /dev/null 2>&1
  # sleep 30
  # kubectl -n elastic-system get configmap elastic-licensing -o json | jq -r '.data'
} # end of operator

###############################################################################################################
# stack
stack() 
{
  echo ""
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} STACK ${BLUE}${VERSION}${green} CLUSTER ${blue}${1}${reset} **************${reset}"
  echo ""

  # create elasticsearch.yaml
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER ${blue}${1}${reset} Creating elasticsearch.yaml"
  cat >> elasticsearch-${1}.yaml <<EOF
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: ${1}
spec:
  version: ${VERSION}
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
EOF

  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER ${blue}${1}${reset} Starting elasticsearch cluster."

  kubectl apply -f elasticsearch-${1}.yaml > /dev/null 2>&1

  # checkeshealth
  checkhealth "elasticsearch" "${1}"

  # create kibana.yaml
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER  ${blue}${1}${reset} Creating kibana.yaml"
    cat >> kibana-${1}.yaml <<EOF
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

  kubectl apply -f kibana-${1}.yaml > /dev/null 2>&1

  #checkkbhealth
  checkhealth "kibana" "${1}"

  createsummary ${1}

} # end of stack

###############################################################################################################
# filebeat autodiscover & metricbeat hosts as daemonset onto k8s hosts
beats()
{
  echo ""
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} STACK ${BLUE}${VERSION}${green} with BEATS **************${reset}"
  echo ""

  # Create and apply metricbeat-rbac
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} Creating BEATS crds"
  cat >> beats-crds.yaml<<EOF
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
EOF

  kubectl apply -f beats-crds.yaml > /dev/null 2>&1

  # Create and apply metricbeat-rbac
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} Creating BEATS"
  cat >> beats.yaml<<EOF
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
      schedule: '@every 5s'
      hosts: ["${1}-es-http.default.svc:9200"]
    - type: tcp
      schedule: '@every 5s'
      hosts: ["${1}-kb-http.default.svc:5601"]
  deployment:
    replicas: 1
    podTemplate:
      spec:
        securityContext:
          runAsUser: 0
EOF

  kubectl apply -f beats.yaml  > /dev/null 2>&1

  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} filebeat, metricbeat, packetbeat, & heartbeat deployed"
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} Please wait a few minutes for the beats to become healthy. (it will restart 3-4 times before it becomes healthy) & for the data to start showing"
  #sleep 30
  #echo ""
  #kubectl get daemonset
  echo ""

}

###############################################################################################################
# stack monitoring - beats in pods
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
  cat >> monitor1.yaml<<EOF
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

  kubectl apply -f monitor1.yaml > /dev/null 2>&1

  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} Stack monitoring with BEATS in PODS deployed"

  #echo ""
  #kubectl get daemonset
  echo ""
}
###############################################################################################################
# stack monitoring - side car
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

  kubectl apply -f monitor2.yaml > /dev/null 2>&1

  #checkkbhealth
  checkhealth "kibana" "${1}"

  createsummary "${1}"
  echo ""

# notes
# you can create a normal deployment and patch it using kubectl patch kibana eck-lab --type merge -p '{"spec":{"monitoring":{"logs":{"elasticsearchRefs":[{"name":"eck-lab-monitor"}]},"metrics":{"elasticsearchRefs":[{"name":"eck-lab-monitor"}]}}}}' to change it to sidecar monitoring
#

}
###############################################################################################################
# fleet server
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
  sleep 60 & # no healthchecks on fleet so just going to sleep for 60
  while kill -0 $! >/dev/null 2>&1
  do
    echo -n "."
    sleep 2
  done
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

  kubectl apply -f fleet.yaml > /dev/null 2>&1

  # checkfleethealth
  checkhealth "agent" "elastic-agent"

  echo ""

} # end fleet-server


###############################################################################################################
# enterprisesearch

###############################################################################################################
# maps server

###############################################################################################################
# main script

# manually checking versions and limiting version if not cleanup
if [ "${1}" = "operator" ]; then
  ECKVERSION=${2}
elif [ "${1}" != "cleanup" ]; then
  VERSION=${2}
  ECKVERSION=${3}
  # manually limiting elasticsearch version to 7.10.0 or greater
  if [ $(checkversion $VERSION) -lt $(checkversion "7.10.0") ]; then
    echo "${red}[DEBUG]${reset} Script is limited to stack version 7.10.0 and higher"
    echo ""
    help
    exit
  fi

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
  echo "${green}[DEBUG]${reset} This might take a while.  In another window you can ${blue}watch -n2 kubectl get all${reset} or ${blue}kubectl get events -w${reset} to watch the stack being stood up"
  echo ""
fi

# preflight checks before creating directories

checkjq
checkkubectl

case ${1} in
  operator)
    checkdir
    operator
    ;;
  build|start|stack)
    checkdir
    operator
    stack "eck-lab"
    summary
    ;;
  beats|beat)
    checkdir
    operator
    stack "eck-lab"
    beats "eck-lab"
    summary
    ;;
  monitor1)
    checkdir
    operator
    stack "eck-lab"
    stack "eck-lab-monitor"
    monitor1 "eck-lab"
    summary
    ;;
  monitor2)
    if [ $(checkversion $ECKVERSION) -lt $(checkversion "1.7.0") -o $(checkversion $VERSION) -lt $(checkversion "7.14.0") ]; then
      echo "${red}[DEBUG]${reset} Sidecar stack monitoring started with ECK 1.7.0 & STACK 7.14.0.  Please run cleanup and re-run wiht ECK operator 1.7.0+/Stack 7.14.0+"
      echo ""
      help
      exit
    else
      checkdir
      operator
      stack "eck-lab-monitor"
      monitor2 "eck-lab"
      summary
    fi
    ;;
#  snapshot)
#    snapshot ${2} ${3}
#    ;;
  fleet)
    if [ $(checkversion $ECKVERSION) -lt $(checkversion "1.7.0") -o $(checkversion $VERSION) -lt $(checkversion "7.14.0") ]; then
      echo "${red}[DEBUG]${reset} Fleet server started with ECK 1.7.0 and STACK 7.14.0.  Please run cleanup and re-run with ECK operator 1.7.0+/Stack 7.14.0+"
      echo ""
      help
      exit
    else
      checkdir
      operator
      stack "eck-lab"
      fleet "eck-lab"
      summary
    fi
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
