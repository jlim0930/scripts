#!/usr/bin/env bash

# justin lim <justin@isthecoolest.ninja>
#
# version 4.1

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
# eck 2.6+
#   ECK automatically injects CA certs into agent trust store (no bash workaround needed)
#   Logstash CRD (logstash.k8s.elastic.co/v1alpha1)
# eck 3.0+
#   ES 9.0+ support
#   ApmServer CRD removed - APM now managed via Fleet/Elastic Agent APM integration
#   Requires Kubernetes 1.27+

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
# CONFIGURATION — edit these to change defaults without touching function bodies

# Container image registry
ELASTIC_REGISTRY="docker.elastic.co"
# Image used by createcerts() for elasticsearch-certutil; must be 8.x+
CERTUTIL_IMAGE="${ELASTIC_REGISTRY}/elasticsearch/elasticsearch:8.17.6"
# Elastic Helm chart repository
ELASTIC_HELM_REPO="https://helm.elastic.co"
# ECK operator manifest download base URL
ECK_DOWNLOAD_BASE="https://download.elastic.co/downloads/eck"
# Cluster names per deployment mode
HELM_CLUSTER="helm-lab"
NATIVE_CLUSTER="native-lab"

# Service ports
ES_PORT="9200"
KB_PORT="5601"
APM_PORT="8200"

###############################################################################################################
# VERSION FETCH CACHE — populated on first call to fetch_eck_versions / fetch_stack_versions
_ECK_VERSIONS_FETCHED=""
_STACK_VERSIONS_FETCHED=""
###############################################################################################################

###############################################################################################################
# colors
red=$(tput setaf 1)
green=$(tput setaf 2)
blue=$(tput setaf 14)
reset=$(tput sgr0)

###############################################################################################################

# help
help()
{
  echo ""
  echo "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"
  echo "${green}  ELASTIC STACK ON KUBERNETES  —  $(basename "$0")${reset}"
  echo "${green}  Run with a command name; ECK and Stack versions are selected interactively.${reset}"
  echo "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"
  echo ""
  echo "  ${green}PREREQUISITES:${reset} jq · openssl · docker (running) · kubectl · helm"
  echo "  ${green}WORKDIR:${reset}       ${blue}${WORKDIR}${reset}  (yaml files · notes · ca.crt)"
  echo ""
  echo "  ${green}NOTE:${reset} Stack 8.x → ECK 2.2.0+ · Stack 9.x → ECK 3.0.0+ (Kubernetes 1.27+)"
  echo ""
  echo "${blue}──── ECK OPERATOR — base deployments ────────────────────────────────────────────${reset}"
  echo "  ${green}operator${reset}         Install ECK operator only (no ES/Kibana)"
  echo "  ${green}stack${reset}            ECK-managed Elasticsearch + Kibana                [ECK 1.4+ | Stack 7.10+]"
  echo "  ${green}dedicated${reset}        ECK stack with dedicated master + data nodes       [ECK 1.4+ | Stack 7.10+]"
  echo "  ${green}helmeck${reset}          ECK operator via Helm + ES + Kibana               [ECK 2.0+ | Stack 7.10+]"
  echo "  ${green}stackpolicy${reset}      stack + StackConfigurationPolicy                  [ECK 2.6+ | Stack 7.10+]"
  echo "  ${green}fleet${reset}            stack + Fleet Server + Elastic Agent              [ECK 1.7+ | Stack 7.14+]"
  echo "  ${green}fleet-nonroot${reset}    stack + Fleet + Elastic Agent, non-root           [ECK 2.6+ | Stack 7.14+]"
  echo ""
  echo "${blue}──── NON-OPERATOR — base deployments ────────────────────────────────────────────${reset}"
  echo "  ${green}helm${reset}             ES + Kibana via Elastic Helm charts (no operator) [Stack 7.14–7.17.x only]"
  echo "  ${green}native${reset}           ES + Kibana via native Kubernetes manifests        [Stack 7.3–8.x only]"
  echo ""
  echo "${blue}──── ADD-ON COMMANDS — layer onto an existing deployment ────────────────────────${reset}"
  echo "  ${green}add-ldap${reset}                   OpenLDAP + configure ES LDAP realm           [eck|helmeck|helm]"
  echo "  ${green}add-beats${reset}                  Filebeat + Metricbeat + Packetbeat + Heartbeat [eck|helmeck|helm|native]"
  echo "  ${green}add-monitor1${reset}               Monitoring cluster + beats-in-pods            [eck|helmeck]"
  echo "  ${green}add-monitor2${reset}               Sidecar monitoring (ECK 1.7+ / Stack 7.14+)   [eck|helmeck]"
  echo "  ${green}add-fleet${reset}                  Fleet Server + Elastic Agent (ECK 1.7+ / Stack 7.14+) [eck|helmeck]"
  echo "  ${green}add-fleet-nonroot${reset}          Fleet + Agent, non-root (ECK 2.6+)            [eck|helmeck]"
  echo "  ${green}add-apm${reset}                    Standalone APM Server (${red}7.x–8.x, not ECK 3.0+${reset}) [eck|helmeck]"
  echo "  ${green}add-logstash${reset}               Logstash + beats via Logstash                 [eck|helmeck|helm]"
  echo "  ${green}add-stack-policy${reset}           StackConfigurationPolicy (ECK 2.6+)           [eck|helmeck]"
  echo "  ${green}add-agent-deploy${reset}           Standalone agent Deployment, root (needs fleet) [eck|helmeck]"
  echo "  ${green}add-agent-ds${reset}               Standalone agent DaemonSet, root (needs fleet) [eck|helmeck]"
  echo "  ${green}add-agent-deploy-nonroot${reset}   Standalone agent Deployment, non-root (needs fleet) [eck|helmeck]"
  echo "  ${green}add-agent-ds-nonroot${reset}       Standalone agent DaemonSet, non-root (needs fleet) [eck|helmeck]"
  echo ""
  echo "${blue}──── UTILITY ─────────────────────────────────────────────────────────────────────${reset}"
  echo "  ${green}cleanup${reset}          Remove all resources and ${WORKDIR}"
  echo "  ${green}info|summary${reset}     Show current deployment endpoints and credentials"
  echo ""
  echo "${blue}──── LEGACY COMBINED COMMANDS (stack + add-on in one step, interactive version select) ──${reset}"
  echo "  ECK-based:    ${green}eckldap  beats  monitor1  monitor2  eckapm${reset}"
  echo "  Helm-based:   ${green}helmldap  helmbeats  helmlogstashbeats  helmmonitor${reset}"
  echo "  Native-based: ${green}nativebeats  nativemonitor${reset}"
  echo ""
} # end of help

# FUNCTION - fetch_eck_versions
# Fetches ECK operator releases from GitHub (non-prerelease, sorted descending)
# Sets global: _ECK_VERSIONS_FETCHED (space-separated version strings)
fetch_eck_versions() {
  [ -n "${_ECK_VERSIONS_FETCHED}" ] && return 0
  echo "${green}[DEBUG]${reset} Fetching ECK operator versions from GitHub..."
  local raw
  raw=$(curl -sSf --max-time 15 \
    "https://api.github.com/repos/elastic/cloud-on-k8s/releases?per_page=100" 2>/dev/null) || {
    echo "${red}[DEBUG]${reset} Failed to fetch ECK versions from GitHub. Check internet connectivity."
    exit 1
  }
  _ECK_VERSIONS_FETCHED=$(printf '%s' "${raw}" \
    | jq -r '.[] | select(.prerelease==false and .draft==false) | .tag_name' \
    | sed 's/^v//' | sort -rV | tr '\n' ' ')
  [ -z "${_ECK_VERSIONS_FETCHED}" ] && {
    echo "${red}[DEBUG]${reset} No ECK versions returned from GitHub API."
    exit 1
  }
} # end fetch_eck_versions

# FUNCTION - fetch_stack_versions
# Fetches Elasticsearch releases from GitHub (non-prerelease, latest patch per minor, sorted descending)
# Sets global: _STACK_VERSIONS_FETCHED (space-separated version strings)
fetch_stack_versions() {
  [ -n "${_STACK_VERSIONS_FETCHED}" ] && return 0
  echo "${green}[DEBUG]${reset} Fetching Elasticsearch versions from GitHub..."
  local all_raw="" page_data count
  for page in 1 2 3 4; do
    page_data=$(curl -sSf --max-time 15 \
      "https://api.github.com/repos/elastic/elasticsearch/releases?per_page=100&page=${page}" 2>/dev/null) || break
    count=$(printf '%s' "${page_data}" | jq 'length' 2>/dev/null || echo 0)
    [ "${count}" -eq 0 ] && break
    all_raw="${all_raw}$(printf '%s' "${page_data}" \
      | jq -r '.[] | select(.prerelease==false and .draft==false) | .tag_name' \
      | sed 's/^v//')"$'\n'
  done
  [ -z "${all_raw}" ] && {
    echo "${red}[DEBUG]${reset} No Elasticsearch versions returned from GitHub API."
    exit 1
  }
  # Keep only the latest patch release per minor version, major 7–9, sorted newest first
  _STACK_VERSIONS_FETCHED=$(printf '%s' "${all_raw}" \
    | grep -E '^[789]\.' | sort -rV | awk -F. '!seen[$1"."$2]++' | tr '\n' ' ')
} # end fetch_stack_versions

# FUNCTION - choose_eckversion
# Interactive ECK operator version selection from GitHub releases
# Usage: choose_eckversion MIN_ECK [MAX_ECK]   (MAX_ECK exclusive, default 99.99.99)
# Sets global: ECKVERSION
choose_eckversion() {
  local MIN_ECK="${1:-1.4.0}"
  local MAX_ECK="${2:-99.99.99}"
  fetch_eck_versions

  local -a VLIST=()
  for v in ${_ECK_VERSIONS_FETCHED}; do
    if [ "$(checkversion "${v}")" -ge "$(checkversion "${MIN_ECK}")" ] && \
       [ "$(checkversion "${v}")" -lt "$(checkversion "${MAX_ECK}")" ]; then
      VLIST+=("${v}")
    fi
  done

  if [ "${#VLIST[@]}" -eq 0 ]; then
    echo "${red}[DEBUG]${reset} No ECK versions found in range ${MIN_ECK}–${MAX_ECK}."
    exit 1
  fi

  echo ""
  echo "${green}Available ECK operator versions (newest first):${reset}"
  echo ""
  local i=1
  for v in "${VLIST[@]}"; do
    printf "  ${blue}%2d)${reset}  %s\n" "${i}" "${v}"
    ((i++))
  done
  echo ""
  local CHOICE
  while true; do
    printf "%s" "${green}Select ECK version [1-$((i-1))]: ${reset}"
    read -r CHOICE
    if [[ "${CHOICE}" =~ ^[0-9]+$ ]] && [ "${CHOICE}" -ge 1 ] && [ "${CHOICE}" -le "$((i-1))" ]; then
      ECKVERSION="${VLIST[$((CHOICE-1))]}"
      echo "${green}[DEBUG]${reset} ECK operator version: ${blue}${ECKVERSION}${reset}"
      return 0
    fi
    echo "${red}Invalid. Enter a number between 1 and $((i-1)).${reset}"
  done
} # end choose_eckversion

# FUNCTION - choose_stackversion
# Interactive Stack version selection filtered by ECK version compatibility
# Usage: choose_stackversion MIN_STACK
# Sets global: VERSION
choose_stackversion() {
  local MIN_STACK="${1:-7.10.0}"
  fetch_stack_versions

  local max_major
  if [ "$(checkversion "${ECKVERSION}")" -ge "$(checkversion "3.0.0")" ]; then
    max_major=9
  elif [ "$(checkversion "${ECKVERSION}")" -ge "$(checkversion "2.2.0")" ]; then
    max_major=8
  else
    max_major=7
  fi

  local -a VLIST=()
  local major
  for v in ${_STACK_VERSIONS_FETCHED}; do
    major=$(printf '%s' "${v}" | cut -d. -f1)
    if [ "${major}" -le "${max_major}" ] && \
       [ "$(checkversion "${v}")" -ge "$(checkversion "${MIN_STACK}")" ]; then
      VLIST+=("${v}")
    fi
  done

  if [ "${#VLIST[@]}" -eq 0 ]; then
    echo "${red}[DEBUG]${reset} No compatible Stack versions for ECK ${ECKVERSION} (min ${MIN_STACK})."
    exit 1
  fi

  echo ""
  echo "${green}Available Stack versions for ECK ${blue}${ECKVERSION}${green} (newest first):${reset}"
  echo ""
  local i=1
  for v in "${VLIST[@]}"; do
    printf "  ${blue}%2d)${reset}  %s\n" "${i}" "${v}"
    ((i++))
  done
  echo ""
  local CHOICE
  while true; do
    printf "%s" "${green}Select Stack version [1-$((i-1))]: ${reset}"
    read -r CHOICE
    if [[ "${CHOICE}" =~ ^[0-9]+$ ]] && [ "${CHOICE}" -ge 1 ] && [ "${CHOICE}" -le "$((i-1))" ]; then
      VERSION="${VLIST[$((CHOICE-1))]}"
      echo "${green}[DEBUG]${reset} Stack version: ${blue}${VERSION}${reset}"
      return 0
    fi
    echo "${red}Invalid. Enter a number between 1 and $((i-1)).${reset}"
  done
} # end choose_stackversion

# FUNCTION - choose_stackversion_noeck
# Interactive Stack version selection without ECK (for helm/native modes)
# Usage: choose_stackversion_noeck MIN_STACK MAX_MAJOR
# Sets global: VERSION
choose_stackversion_noeck() {
  local MIN_STACK="${1:-7.3.0}"
  local MAX_MAJOR="${2:-8}"
  fetch_stack_versions

  local -a VLIST=()
  local major
  for v in ${_STACK_VERSIONS_FETCHED}; do
    major=$(printf '%s' "${v}" | cut -d. -f1)
    if [ "${major}" -le "${MAX_MAJOR}" ] && \
       [ "$(checkversion "${v}")" -ge "$(checkversion "${MIN_STACK}")" ]; then
      VLIST+=("${v}")
    fi
  done

  if [ "${#VLIST[@]}" -eq 0 ]; then
    echo "${red}[DEBUG]${reset} No Stack versions found (min ${MIN_STACK}, max ${MAX_MAJOR}.x)."
    exit 1
  fi

  echo ""
  echo "${green}Available Stack versions (newest first):${reset}"
  echo ""
  local i=1
  for v in "${VLIST[@]}"; do
    printf "  ${blue}%2d)${reset}  %s\n" "${i}" "${v}"
    ((i++))
  done
  echo ""
  local CHOICE
  while true; do
    printf "%s" "${green}Select Stack version [1-$((i-1))]: ${reset}"
    read -r CHOICE
    if [[ "${CHOICE}" =~ ^[0-9]+$ ]] && [ "${CHOICE}" -ge 1 ] && [ "${CHOICE}" -le "$((i-1))" ]; then
      VERSION="${VLIST[$((CHOICE-1))]}"
      echo "${green}[DEBUG]${reset} Stack version: ${blue}${VERSION}${reset}"
      return 0
    fi
    echo "${red}Invalid. Enter a number between 1 and $((i-1)).${reset}"
  done
} # end choose_stackversion_noeck

#############################################################
# FUNCTIONS - HELPER
#############################################################

# FUNCTION - spinner
spinner() {
  local PROC="${1}"

  tput civis

  # Clear Line
  CL=$'\e[2K'
  # Spinner Character
  SPINNER="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

  while [ "$(ps -ef | grep -c "${PROC}")" -ge 2 ]; do
    for (( i=0; i<${#SPINNER}; i++ )); do
      sleep 0.05
      printf '%s%s %s\r' "${CL}" "${SPINNER:$i:1}" "${2}"
    done
  done

  tput cnorm
} # end spinner

# FUNCTION - checkjq
checkjq() {
  if ! [ -x "$(command -v jq)" ]; then
    echo "${red}[DEBUG]${reset} jq is not installed.  Please install jq and try again."
    exit 1
  else
    echo "${green}[DEBUG]${reset} jq found"
  fi
} # end checkjq

# FUNCTION - checkopenssl
checkopenssl() {
  if ! [ -x "$(command -v openssl)" ]; then
    echo "${red}[DEBUG]${reset} openssl is not installed.  Please install openssl and try again."
    exit 1
  else
    echo "${green}[DEBUG]${reset} openssl found"
  fi
} # end checkopenssl

# FUNCTION - checkdocker
checkdocker() {
  # check to ensure docker is installed or exit
  if ! docker info >/dev/null 2>&1; then
    echo "${red}[DEBUG]${reset} Docker is not running or you are not part of the docker group.  Please install docker and ensure that you are part of the docker group and try again."
    exit 1
  else
    echo "${green}[DEBUG]${reset} docker found & running"
  fi
} # end checkdocker

# FUNCTION - kubectl
checkkubectl()
{
  if [ "$(kubectl version 2>/dev/null | grep -c "Client Version")" -lt 1 ]; then
    echo "${red}[DEBUG]${reset} kubectl is not installed.  Please install kubectl and try again."
    exit 1
  else
    echo "${green}[DEBUG]${reset} kubectl found"
  fi
  if [ "$(kubectl version 2>/dev/null | grep -c "Server Version")" -lt 1 ]; then
    echo "${red}[DEBUG]${reset} kubectl is not connecting to any kubernetes environment"
    echo "${red}[DEBUG]${reset} if you did not setup your k8s environment.  Please configure your kubernetes context and try again"
    exit 1
  fi
} # end checkubectl

# FUNCTION - helm
checkhelm()
{
  if ! [ -x "$(command -v helm)" ]; then
    echo "${red}[DEBUG]${reset} helm is not installed.  Please install helm and try again. https://helm.sh/docs/intro/install/"
    exit 1
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
  if [ -d "${WORKDIR}" ]; then
    echo "${red}[DEBUG]${reset} Looks like ${WORKDIR} already exists."
    echo "${red}[DEBUG]${reset} Please run ${blue}$(basename "$0") cleanup${reset} before trying again"
    echo ""
    help
    exit 1
  fi

  mkdir -p "${WORKDIR}"
  cd "${WORKDIR}" || { echo "${red}[DEBUG]${reset} Failed to cd into ${WORKDIR}"; exit 1; }
  mkdir temp
  [ -n "${VERSION}" ]    && echo "${VERSION}"    > VERSION
  [ -n "${ECKVERSION}" ] && echo "${ECKVERSION}" > ECKVERSION

} # end checkdir

# FUNCTION - checkcontainerimage
checkcontainerimage() {
  # check to see if the container image exists or not
  if ! docker manifest inspect "${1}" >/dev/null 2>&1; then
    echo "${red}[DEBUG]${reset} Image ${blue}${1}${reset} does not exist.  Please verify and try again"
    exit 1
  else
    echo "${green}[DEBUG]${reset} container image ${blue}${1}${reset} is valid"
  fi
} # end checkcontainerimage

# FUNCTION - checkrequiredversion
checkrequiredversion() {
  # manually limiting eck version to 1.4 or greater
  if [ "$(checkversion "$ECKVERSION")" -lt "$(checkversion "1.4.0")" ]; then
    echo "${red}[DEBUG]${reset} Script is limited to operator 1.4.0 and higher"
    echo ""
    help
    exit 1
  else
    if [ "$(checkversion "$ECKVERSION")" -lt "$(checkversion "1.7.0")" ]; then
      if curl -sL --fail "${ECK_DOWNLOAD_BASE}/${ECKVERSION}/all-in-one.yaml" -o /dev/null; then
        echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} version validated."
      else
        echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} version is invalid."
        echo ""; help; exit 1
      fi
    elif [ "$(checkversion "$ECKVERSION")" -ge "$(checkversion "1.7.0")" ]; then
      if curl -sL --fail "${ECK_DOWNLOAD_BASE}/${ECKVERSION}/crds.yaml" -o /dev/null; then
        echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} version validated."
      else
        echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} version is invalid."
        echo ""; help; exit 1
      fi
    fi
  fi
  if [ "$(checkversion "$ECKVERSION")" -lt "$(checkversion "2.2.0")" ] && [ "$(checkversion "$VERSION")" -ge "$(checkversion "8.0.0")" ]; then
    echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} Can not run 8.x.  Please use operator 2.2.0+"
    echo ""
    help
    exit 1
  fi
  if [ "$(checkversion "$VERSION")" -ge "$(checkversion "9.0.0")" ] && [ "$(checkversion "$ECKVERSION")" -lt "$(checkversion "3.0.0")" ]; then
    echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} Can not run 9.x.  Please use operator 3.0.0+"
    echo ""
    help
    exit 1
  fi

  # manually limiting elasticsearch version to 7.10.0 or greater
  if [ "$(checkversion "$VERSION")" -lt "$(checkversion "7.10.0")" ]; then
    echo "${red}[DEBUG]${reset} This command is limited to stack version 7.10.0 and higher"
    echo ""
    help
    exit 1
  fi

  echo "${green}[DEBUG]${reset} This might take a while.  In another window you can ${blue}watch -n2 kubectl get all${reset} or ${blue}kubectl get events -w${reset} to watch the stack being stood up"
  echo ""

} # end checkrequiredversion

# FUNCTION - checkrequiredversionhelm
checkrequiredversionhelm() {
  # manually limiting version to 7.14.0+ to -8.0.0
  if [ "$(checkversion "$VERSION")" -lt "$(checkversion "7.14.0")" ] || [ "$(checkversion "$VERSION")" -ge "$(checkversion "8.0.0")" ]; then
    echo "${red}[DEBUG]${reset} This command is limited to stack version 7.14.0+ & < 8.0.0"
    echo ""
    help
    exit 1
  fi
} # end checkrequiredversionhelm

# FUNCTION - checkrequiredversionnative
checkrequiredversionnative() {
  # manually limiting version to value
  if [ "$(checkversion "$VERSION")" -lt "$(checkversion "${1}")" ]; then
    echo "${red}[DEBUG]${reset} This command is limited to stack version ${1}"
    echo ""
    help
    exit 1
  fi
} # end checkrequiredversionnative

# FUNCTION - checkhealth
checkhealth() {
  sleep 3
  echo ""
  until [ "$(kubectl get "${1}" "${2}" -ojson 2>/dev/null | jq -r '.status.'${3}'')" == "${4}" ]; do
    sleep 2
  done &
  spinner $! "${blue}[DEBUG]${reset} Checking to ensure all ${3}(${4}) are ready for ${2}.  IF this does not finish in ~5 minutes something is wrong"
  echo ""
  kubectl get "${1}" "${2}" | sed "s/^/                     /"
  echo ""
} # end checkhealth

############################################################

# FUNCTION - check_prerequisites
# Usage: check_prerequisites [helm]
# Runs all standard prerequisite checks; pass "helm" to also verify helm is installed.
check_prerequisites() {
  checkjq
  checkdocker
  checkkubectl
  checkopenssl
  if [ "${1}" = "helm" ]; then
    checkhelm
  fi
} # end check_prerequisites

# FUNCTION - apply_trial_license
# Creates and applies an ECK enterprise trial license secret in elastic-system.
apply_trial_license() {
  echo "${green}[DEBUG]${reset} Creating ECK trial license"
  cat > "${WORKDIR}/license.yaml" <<EOF
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
  kubectl apply -f "${WORKDIR}/license.yaml" >/dev/null 2>&1
} # end apply_trial_license

# FUNCTION - helm_add_elastic_repo
# Adds the Elastic Helm chart repository and updates the repo cache.
helm_add_elastic_repo() {
  helm repo add elastic "${ELASTIC_HELM_REPO}" >/dev/null 2>&1
  helm repo update >/dev/null 2>&1
} # end helm_add_elastic_repo

# FUNCTION - sleep_with_spinner
# Usage: sleep_with_spinner SECONDS "description message"
sleep_with_spinner() {
  sleep "${1}" &
  spinner $! "${blue}[DEBUG]${reset} ${2}"
  echo ""
} # end sleep_with_spinner

# FUNCTION - wait_for_ip
# Polls kubectl get service for a valid external IP, up to 30 attempts.
# Usage: IP=$(wait_for_ip GREP_PATTERN "description")
wait_for_ip() {
  local grep_pattern="${1}" desc="${2}"
  local ip="" c=0
  while [ "${ip}" = "" ] || [ "${ip}" = "<pending>" ]; do
    ip=$(kubectl get service 2>/dev/null | grep "${grep_pattern}" | grep -v headless | awk '{ print $4 }')
    sleep 1
    ((c++))
    if [ "${c}" -eq 30 ]; then
      echo "${red}[DEBUG]${reset} Unable to get ${desc} endpoint after 30 seconds." >&2
      exit 1
    fi
  done
  echo "${ip}"
} # end wait_for_ip

# FUNCTION - wait_for_secret_value
# Polls a k8s secret for a non-empty decoded value, up to 30 attempts.
# Usage: VAL=$(wait_for_secret_value SECRET_NAME GO_TEMPLATE "description")
wait_for_secret_value() {
  local secret="${1}" tmpl="${2}" desc="${3}"
  local val="" c=0
  while [ "${val}" = "" ]; do
    val=$(kubectl get secret "${secret}" -o go-template="${tmpl}" 2>/dev/null)
    sleep 1
    ((c++))
    if [ "${c}" -eq 30 ]; then
      echo "${red}[DEBUG]${reset} Unable to get ${desc} after 30 seconds." >&2
      exit 1
    fi
  done
  echo "${val}"
} # end wait_for_secret_value

############################################################

# FUNCTION - createsummary
createsummary()
{
  if [ -e "${WORKDIR}/ECK" ] || [ -e "${WORKDIR}/HELMECK" ]; then
    PASSWORD=$(wait_for_secret_value "${1}-es-elastic-user" '{{.data.elastic | base64decode}}' "elastic password")
    echo "${green}[DEBUG]${reset} Grabbed elastic password for ${1}: ${blue}${PASSWORD}${reset}"
    echo "${1} elastic password: ${PASSWORD}" >> notes

    ESIP=$(wait_for_ip "${1}-es-http" "elasticsearch")
    echo "${green}[DEBUG]${reset} Grabbed elasticsearch endpoint for ${1}: ${blue}https://${ESIP}:${ES_PORT}${reset}"
    echo "${1} elasticsearch endpoint: https://${ESIP}:${ES_PORT}" >> notes

    KIBANAIP=$(wait_for_ip "${1}-kb-http" "kibana")
    echo "${green}[DEBUG]${reset} Grabbed kibana endpoint for ${1}: ${blue}https://${KIBANAIP}:${KB_PORT}${reset}"
    echo "${1} kibana endpoint: https://${KIBANAIP}:${KB_PORT}" >> notes

    kubectl get secrets "${1}-es-http-certs-public" -o jsonpath="{.data.ca\.crt}" | base64 -d > "${WORKDIR}/ca.crt"

  elif [ -e "${WORKDIR}/HELM" ]; then
    PASSWORD=$(wait_for_secret_value "elastic-credentials" '{{.data.password | base64decode}}' "elastic password")
    echo "${green}[DEBUG]${reset} Grabbed elastic password for ${1}: ${blue}${PASSWORD}${reset}"
    echo "${1} elastic password: ${PASSWORD}" >> notes

    ESIP=$(wait_for_ip "${1}-es-default" "elasticsearch")
    echo "${green}[DEBUG]${reset} Grabbed elasticsearch endpoint for ${1}: ${blue}https://${ESIP}:${ES_PORT}${reset}"
    echo "${1} elasticsearch endpoint: https://${ESIP}:${ES_PORT}" >> notes

    KIBANAIP=$(wait_for_ip "${HELM_CLUSTER}-kb-kibana" "kibana")
    echo "${green}[DEBUG]${reset} Grabbed kibana endpoint for ${1}: ${blue}https://${KIBANAIP}:${KB_PORT}${reset}"
    echo "${1} kibana endpoint: https://${KIBANAIP}:${KB_PORT}" >> notes

  elif [ -e "${WORKDIR}/NATIVE" ]; then
    PASSWORD=$(wait_for_secret_value "elastic-credentials" '{{.data.password | base64decode}}' "elastic password")
    echo "${green}[DEBUG]${reset} Grabbed elastic password for ${1}: ${blue}${PASSWORD}${reset}"
    echo "${1} elastic password: ${PASSWORD}" >> notes

    ESIP=$(wait_for_ip "${1}-default" "elasticsearch")
    echo "${green}[DEBUG]${reset} Grabbed elasticsearch endpoint for ${1}: ${blue}https://${ESIP}:${ES_PORT}${reset}"
    echo "${1} elasticsearch endpoint: https://${ESIP}:${ES_PORT}" >> notes

    KIBANAIP=$(wait_for_ip "${NATIVE_CLUSTER}-kibana" "kibana")
    echo "${green}[DEBUG]${reset} Grabbed kibana endpoint for ${1}: ${blue}https://${KIBANAIP}:${KB_PORT}${reset}"
    echo "${1} kibana endpoint: https://${KIBANAIP}:${KB_PORT}" >> notes
  fi

  echo ""
} # end createsummary

# FUNCTION - print_notes
# Prints each line from WORKDIR/notes with the value coloured.
print_notes() {
  while IFS=': ' read -r key val; do
    echo "${key}: ${blue}${val}${reset}"
  done < "${WORKDIR}/notes"
} # end print_notes

# FUNCTION - summary
summary()
{
  local title="" eckinfo=""
  if [ -e "${WORKDIR}/ECK" ]; then
    title="ECK ${ECKVERSION} STACK ${VERSION}"
    eckinfo="yes"
  elif [ -e "${WORKDIR}/HELMECK" ]; then
    title="HELMECK (ECK via Helm) ${ECKVERSION} STACK ${VERSION}"
    eckinfo="yes"
  elif [ -e "${WORKDIR}/HELM" ]; then
    title="HELM STACK ${VERSION}"
  elif [ -e "${WORKDIR}/NATIVE" ]; then
    title="NATIVE STACK ${VERSION}"
  fi

  [ -z "${title}" ] && return

  echo ""
  echo "${green}[SUMMARY]${reset} ${blue}${title}${reset}"
  echo ""
  kubectl get all | sed "s/^/                     /"
  echo ""
  echo "${green}[SUMMARY]${reset} STACK INFO:"
  print_notes
  echo ""
  echo "${green}[SUMMARY]${reset} ${blue}ca.crt${reset} is located in ${blue}${WORKDIR}/ca.crt${reset}"
  echo ""
  if [ -n "${eckinfo}" ]; then
    echo "${green}[NOTE]${reset} If you missed the summary its also in ${blue}${WORKDIR}/notes${reset}"
    echo "${green}[NOTE]${reset} You can start logging into kibana but please give things a few minutes for proper startup."
    echo ""
  fi
} # end summary

# FUNCTION - beatsetup
beatsetup()
{

  echo "${green}[DEBUG]${reset} Running setup for ${1}.."
  kubectl delete pod beats-setup >/dev/null 2>&1
  kubectl run -it beats-setup --image=docker.elastic.co/beats/"${1}":"${VERSION}" -- sh -c "${1} setup -E output.elasticsearch.hosts=\"${ESIP}:9200\" -E output.elasticsearch.protocol=https -E output.elasticsearch.username=elastic -E output.elasticsearch.password=${PASSWORD} -E output.elasticsearch.ssl.verification_mode=none -E setup.kibana.host=\"${KIBANAIP}:5601\" -E setup.kibana.protocol=https -E setup.kibana.username=elastic -E setup.kibana.password=${PASSWORD} -E setup.kibana.ssl.verification_mode=none -E setup.ilm.overwrite=true" >/dev/null 2>&1
  kubectl delete pod beats-setup >/dev/null 2>&1

} # end beatsetup

# FUNCTION - getchartversion
# Returns the latest available helm chart version for a given major.minor version
getchartversion() {
  local version="${1}"
  local chart="${2:-elasticsearch}"
  local major_minor
  major_minor=$(echo "${version}" | cut -d. -f1-2)
  helm search repo "elastic/${chart}" --versions 2>/dev/null | awk '{print $2}' | grep "^${major_minor}\." | sort -V | tail -1
}

# FUNCTION - createcerts
createcerts() {
  echo ""
  echo "${green}[DEBUG]${reset} Creating ca.crt and certificate/key for ${1}"
  docker rm -f "${1}-certs" >/dev/null 2>&1
  docker run --name "${1}-certs" -i \
  "${CERTUTIL_IMAGE}" \
    /bin/sh -c " \
      elasticsearch-certutil ca --silent --pem -out /tmp/ca.zip && \
      unzip /tmp/ca.zip -d /tmp && \
      elasticsearch-certutil cert --silent --pem -out /tmp/${1}.zip --name ${1} --dns ${1} --ca-cert /tmp/ca/ca.crt --ca-key /tmp/ca/ca.key && \
      unzip /tmp/${1}.zip -d /tmp
  " >/dev/null 2>&1
  mkdir "${WORKDIR}/${1}-certs" >/dev/null 2>&1
  docker cp "${1}-certs":/tmp/ca/ca.crt "${WORKDIR}/${1}-certs/"
  docker cp "${1}-certs":/tmp/ca/ca.key "${WORKDIR}/${1}-certs"
  docker cp "${1}-certs":/tmp/${1}/${1}.crt "${WORKDIR}/${1}-certs"
  docker cp "${1}-certs":/tmp/${1}/${1}.key "${WORKDIR}/${1}-certs"
  docker rm -f "${1}-certs" >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating secret ${1}-certificates"
  kubectl create secret generic "${2}" --from-file="${WORKDIR}/${1}-certs/ca.crt" --from-file="${WORKDIR}/${1}-certs/${1}.crt" --from-file="${WORKDIR}/${1}-certs/${1}.key" >/dev/null 2>&1

} # end createcerts

#############################################################
# FUNCTIONS - STATE MANAGEMENT (for addon commands)
#############################################################

# FUNCTION - loadstate
# Reads deployment state from an existing WORKDIR so addon commands can operate on it
loadstate()
{
  if [ ! -d "${WORKDIR}" ]; then
    echo "${red}[DEBUG]${reset} No deployment found at ${blue}${WORKDIR}${reset}."
    echo "${red}[DEBUG]${reset} Run a base deployment command first (stack, helmeck, helm, or native)."
    echo ""
    help
    exit 1
  fi

  VERSION=$(cat "${WORKDIR}/VERSION" 2>/dev/null)
  ECKVERSION=$(cat "${WORKDIR}/ECKVERSION" 2>/dev/null)
  cd "${WORKDIR}" || { echo "${red}[DEBUG]${reset} Failed to cd into ${WORKDIR}"; exit 1; }

  if [ -e "${WORKDIR}/ECK" ] || [ -e "${WORKDIR}/HELMECK" ]; then
    PASSWORD=$(kubectl get secret eck-lab-es-elastic-user -o go-template='{{.data.elastic | base64decode}}' 2>/dev/null)
    ESIP=$(kubectl get service 2>/dev/null | grep eck-lab-es-http | awk '{ print $4 }')
    KIBANAIP=$(kubectl get service 2>/dev/null | grep eck-lab-kb-http | awk '{ print $4 }')
  elif [ -e "${WORKDIR}/HELM" ]; then
    PASSWORD=$(kubectl get secrets elastic-credentials -o go-template='{{.data.password | base64decode}}' 2>/dev/null)
    ESIP=$(kubectl get service 2>/dev/null | grep helm-lab-es-default | grep -v headless | awk '{ print $4 }')
    KIBANAIP=$(kubectl get service 2>/dev/null | grep helm-lab-kb-kibana | awk '{ print $4 }')
  elif [ -e "${WORKDIR}/NATIVE" ]; then
    PASSWORD=$(kubectl get secrets elastic-credentials -o go-template='{{.data.password | base64decode}}' 2>/dev/null)
    ESIP=$(kubectl get service 2>/dev/null | grep native-lab-default | grep -v headless | awk '{ print $4 }')
    KIBANAIP=$(kubectl get service 2>/dev/null | grep native-lab-kibana | awk '{ print $4 }')
  fi

  if [ -z "${VERSION}" ]; then
    echo "${red}[DEBUG]${reset} Could not determine stack version from ${blue}${WORKDIR}/VERSION${reset}."
    exit 1
  fi

  echo "${green}[DEBUG]${reset} Loaded state: STACK ${blue}${VERSION}${reset} ECKVERSION ${blue}${ECKVERSION:-n/a}${reset}"
  echo "${green}[DEBUG]${reset} ES endpoint: ${blue}https://${ESIP}:9200${reset}"
} # end loadstate

# FUNCTION - checkexistingdeployment
# Validates that the current deployment supports the requested addon
checkexistingdeployment()
{
  local REQUIRED_TYPE="${1}"  # "eck", "helm", "native", "any"

  if [ ! -d "${WORKDIR}" ]; then
    echo "${red}[DEBUG]${reset} No deployment found. Run a base deployment command first."
    exit 1
  fi

  DEPLOY_TYPE="unknown"
  if [ -e "${WORKDIR}/ECK" ]; then
    DEPLOY_TYPE="eck"
  elif [ -e "${WORKDIR}/HELMECK" ]; then
    DEPLOY_TYPE="helmeck"
  elif [ -e "${WORKDIR}/HELM" ]; then
    DEPLOY_TYPE="helm"
  elif [ -e "${WORKDIR}/NATIVE" ]; then
    DEPLOY_TYPE="native"
  fi

  case "${REQUIRED_TYPE}" in
    eck)
      if [ "${DEPLOY_TYPE}" != "eck" ] && [ "${DEPLOY_TYPE}" != "helmeck" ]; then
        echo "${red}[DEBUG]${reset} This addon requires an ECK or HELMECK deployment. Current deployment: ${blue}${DEPLOY_TYPE}${reset}"
        exit 1
      fi
      ;;
    helm)
      if [ "${DEPLOY_TYPE}" != "helm" ]; then
        echo "${red}[DEBUG]${reset} This addon requires a HELM deployment. Current deployment: ${blue}${DEPLOY_TYPE}${reset}"
        exit 1
      fi
      ;;
    any)
      if [ "${DEPLOY_TYPE}" = "unknown" ]; then
        echo "${red}[DEBUG]${reset} Could not determine deployment type from ${blue}${WORKDIR}${reset}."
        exit 1
      fi
      ;;
  esac
} # end checkexistingdeployment

#############################################################
# FUNCTIONS - HELMECK (ECK operator via Helm)
#############################################################

# FUNCTION - helmeck_operator
# Installs the ECK operator using its official Helm chart
helmeck_operator()
{
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} OPERATOR via HELM **************${reset}"
  echo ""

  touch "${WORKDIR}/HELMECK"

  helm_add_elastic_repo

  echo "${green}[DEBUG]${reset} Installing ECK operator via Helm chart elastic/eck-operator ${blue}${ECKVERSION}${reset}"
  if ! helm upgrade --install elastic-operator elastic/eck-operator \
    --version "${ECKVERSION}" \
    -n elastic-system \
    --create-namespace \
    --set=installCRDs=true >/dev/null 2>&1; then
    echo "${red}[DEBUG]${reset} Failed to install ECK operator via helm. Check version and network connectivity."
    echo ""
    help
    exit 1
  fi

  until [ "$(kubectl -n elastic-system get pod 2>/dev/null | grep elastic-operator | awk '{ print $3 }')" = "Running" ]; do
    sleep 2
  done &
  spinner $! "${blue}[DEBUG]${reset} Waiting for ECK operator to become ready. If this does not finish in ~5 minutes something is wrong"
  echo ""
  kubectl -n elastic-system get all | sed "s/^/                     /"

  apply_trial_license

  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} saving ECKVERSION to ${WORKDIR}"
  echo "${ECKVERSION}" > "${WORKDIR}/ECKVERSION"

} # end helmeck_operator

# FUNCTION - helmeck_stackbuild
# Deploys Elasticsearch and Kibana as ECK-managed resources via the eck-elasticsearch and eck-kibana Helm charts
helmeck_stackbuild()
{
  local CLUSTER="${1}"

  echo ""
  echo "${green} ********** Deploying STACK ${blue}${VERSION}${green} via ECK Helm Charts (cluster: ${blue}${CLUSTER}${green}) **************${reset}"
  echo ""

  helm_add_elastic_repo

  echo "${green}[DEBUG]${reset} Creating ECK Elasticsearch Helm values: eck-es-values.yaml"
  cat > "${WORKDIR}/eck-es-values.yaml" <<EOF
fullnameOverride: "${CLUSTER}"
version: "${VERSION}"
nodeSets:
- name: default
  count: 3
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
        command: ['sh', '-c', 'sysctl -w vm.max_map_count=1048576']
http:
  service:
    spec:
      type: LoadBalancer
EOF

  echo "${green}[DEBUG]${reset} Deploying Elasticsearch via ${blue}elastic/eck-elasticsearch${reset} Helm chart"
  if ! helm upgrade --install "${CLUSTER}-es" elastic/eck-elasticsearch -f "${WORKDIR}/eck-es-values.yaml" >/dev/null 2>&1; then
    echo "${red}[DEBUG]${reset} Failed to install Elasticsearch via ECK Helm chart. Ensure eck-operator 2.0.0+ is running."
    exit 1
  fi

  checkhealth "statefulset" "${CLUSTER}-es-default" "readyReplicas" "3"

  echo "${green}[DEBUG]${reset} Creating ECK Kibana Helm values: eck-kb-values.yaml"
  cat > "${WORKDIR}/eck-kb-values.yaml" <<EOF
fullnameOverride: "${CLUSTER}"
version: "${VERSION}"
count: 1
elasticsearchRef:
  name: "${CLUSTER}"
http:
  service:
    spec:
      type: LoadBalancer
podTemplate:
  metadata:
    labels:
      scrape: kb
EOF

  echo "${green}[DEBUG]${reset} Deploying Kibana via ${blue}elastic/eck-kibana${reset} Helm chart"
  if ! helm upgrade --install "${CLUSTER}-kb" elastic/eck-kibana -f "${WORKDIR}/eck-kb-values.yaml" >/dev/null 2>&1; then
    echo "${red}[DEBUG]${reset} Failed to install Kibana via ECK Helm chart."
    exit 1
  fi

  checkhealth "deployment" "${CLUSTER}-kb" "readyReplicas" "1"

  createsummary "${CLUSTER}"

} # end helmeck_stackbuild

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

  if [ -e "${WORKDIR}/ECK" ]; then
    for item in "${WORKDIR}"/*.yaml
    do
      [ -f "${item}" ] || continue
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}${item}${reset}"
      kubectl delete -f "${item}" > /dev/null 2>&1
    done
    kubectl delete secret fleet-server-agent-http-certs-public >/dev/null 2>&1
    if [ -e "${WORKDIR}/logstash.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}logstash${reset}"
      kubectl delete -f "${WORKDIR}/logstash.yaml" >/dev/null 2>&1
      kubectl delete pvc logstash-data-logstash-ls-0 >/dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/beats-logstash.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}beats-logstash${reset}"
      kubectl delete -f "${WORKDIR}/beats-logstash.yaml" >/dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/openldap.yaml" ]; then
      kubectl delete -f "${WORKDIR}/openldap.yaml" >/dev/null 2>&1
      kubectl delete secret openldap openldap-certificates ldapbindpw-secret >/dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/apmserver.yaml" ]; then
      kubectl delete -f "${WORKDIR}/apmserver.yaml" >/dev/null 2>&1
    fi
    kubectl delete secret agent-enroll-token-deploy agent-enroll-token-ds agent-enroll-token-deploy-nonroot agent-enroll-token-ds-nonroot >/dev/null 2>&1
    kubectl delete clusterrole elastic-agent-standalone >/dev/null 2>&1
    kubectl delete clusterrolebinding elastic-agent-standalone >/dev/null 2>&1
    kubectl delete serviceaccount elastic-agent-standalone >/dev/null 2>&1
  elif [ -e "${WORKDIR}/HELMECK" ]; then
    echo "${green}[DEBUG]${reset} DELETING HELMECK resources"
    if [ -e "${WORKDIR}/beats.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}beats${reset}"
      kubectl delete -f "${WORKDIR}/beats.yaml" >/dev/null 2>&1
      kubectl delete -f "${WORKDIR}/beats-crds.yaml" >/dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/fleet.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}fleet${reset}"
      kubectl delete -f "${WORKDIR}/fleet.yaml" >/dev/null 2>&1
      kubectl delete secret fleet-server-agent-http-certs-public >/dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/fleet-nonroot.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}fleet-nonroot${reset}"
      kubectl delete -f "${WORKDIR}/fleet-nonroot.yaml" >/dev/null 2>&1
      kubectl delete secret fleet-server-agent-http-certs-public >/dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/stack-policy.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}stack-policy${reset}"
      kubectl delete -f "${WORKDIR}/stack-policy.yaml" >/dev/null 2>&1
    fi
    for agentfile in "${WORKDIR}"/agent-standalone-*.yaml; do
      [ -f "${agentfile}" ] || continue
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}$(basename "${agentfile}")${reset}"
      kubectl delete -f "${agentfile}" >/dev/null 2>&1
    done
    kubectl delete secret agent-enroll-token-deploy agent-enroll-token-ds agent-enroll-token-deploy-nonroot agent-enroll-token-ds-nonroot >/dev/null 2>&1
    kubectl delete clusterrole elastic-agent-standalone >/dev/null 2>&1
    kubectl delete clusterrolebinding elastic-agent-standalone >/dev/null 2>&1
    kubectl delete serviceaccount elastic-agent-standalone >/dev/null 2>&1
    if [ -e "${WORKDIR}/monitor1.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}monitor1${reset}"
      kubectl delete -f "${WORKDIR}/monitor1.yaml" >/dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/logstash.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}logstash${reset}"
      kubectl delete -f "${WORKDIR}/logstash.yaml" >/dev/null 2>&1
      kubectl delete pvc logstash-data-logstash-ls-0 >/dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/beats-logstash.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}beats-logstash${reset}"
      kubectl delete -f "${WORKDIR}/beats-logstash.yaml" >/dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/openldap.yaml" ]; then
      kubectl delete -f "${WORKDIR}/openldap.yaml" >/dev/null 2>&1
      kubectl delete secret openldap openldap-certificates ldapbindpw-secret >/dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/apmserver.yaml" ]; then
      kubectl delete -f "${WORKDIR}/apmserver.yaml" >/dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/eck-kb-values.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}eck-lab-kb (Helm)${reset}"
      helm uninstall eck-lab-kb >/dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/eck-es-values.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}eck-lab-es (Helm)${reset}"
      helm uninstall eck-lab-es >/dev/null 2>&1
      kubectl delete pvc elasticsearch-data-eck-lab-es-default-0 >/dev/null 2>&1
      kubectl delete pvc elasticsearch-data-eck-lab-es-default-1 >/dev/null 2>&1
      kubectl delete pvc elasticsearch-data-eck-lab-es-default-2 >/dev/null 2>&1
    fi
    echo "${green}[DEBUG]${reset} DELETING ECK operator (Helm)"
    helm uninstall elastic-operator -n elastic-system >/dev/null 2>&1
    kubectl delete namespace elastic-system >/dev/null 2>&1
  elif [ -e "${WORKDIR}/HELM" ]; then
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

    if [ -e "${WORKDIR}/fb-values.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}helm-lab filebeat${reset}"
      helm uninstall helm-lab-fb > /dev/null 2>&1
      kubectl delete secrets beats-credentials > /dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/mb-values.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}helm-lab metricbeat${reset}"
      helm uninstall kube-state-metrics > /dev/null 2>&1
      helm uninstall helm-lab-mb > /dev/null 2>&1
      kubectl delete secrets beats-credentials > /dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/ls-values.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}helm-lab logstash${reset}"
      helm uninstall helm-lab-ls > /dev/null 2>&1
      kubectl delete pvc helm-lab-ls-logstash-helm-lab-ls-logstash-0 > /dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/openldap.yaml" ]; then
      kubectl delete -f "${WORKDIR}/openldap.yaml" >/dev/null 2>&1
      kubectl delete secret openldap openldap-certificates ldapbindpw-secret >/dev/null 2>&1
    fi
  elif [ -e "${WORKDIR}/NATIVE" ]; then
    echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}native-lab kibana${reset}"
    kubectl delete -f "${WORKDIR}/kibana.yaml" > /dev/null 2>&1
    kubectl delete secrets kibana-encryptionkey > /dev/null 2>&1
    kubectl delete secrets kibana-certificates  > /dev/null 2>&1
    kubectl delete secrets kibana-credentials > /dev/null 2>&1
    echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}native-lab elasticsearch${reset}"
    kubectl delete -f "${WORKDIR}/elasticsearch.yaml" > /dev/null 2>&1
    kubectl delete pvc native-lab-default-native-lab-default-0 > /dev/null 2>&1
    kubectl delete pvc native-lab-default-native-lab-default-1 > /dev/null 2>&1
    kubectl delete pvc native-lab-default-native-lab-default-2 > /dev/null 2>&1
    kubectl delete secrets elastic-certificates > /dev/null 2>&1
    kubectl delete secrets elastic-credentials > /dev/null 2>&1

    if [ -e "${WORKDIR}/filebeat-kubernetes.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}native-lab filebeat${reset}"
      kubectl delete -f "${WORKDIR}/filebeat-kubernetes.yaml" > /dev/null 2>&1
      kubectl delete secrets beats-credentials > /dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/metricbeat-kubernetes.yaml" ]; then
      echo "${green}[DEBUG]${reset} DELETING Resources for: ${blue}native-lab metricbeat${reset}"
      kubectl delete -f "${WORKDIR}/kube-state-metrics/examples/standard" > /dev/null 2>&1
      kubectl delete -f "${WORKDIR}/metricbeat-kubernetes.yaml" > /dev/null 2>&1
      kubectl delete secrets beats-credentials > /dev/null 2>&1
    fi
    if [ -e "${WORKDIR}/openldap.yaml" ]; then
      kubectl delete -f "${WORKDIR}/openldap.yaml" >/dev/null 2>&1
      kubectl delete secret openldap openldap-certificates ldapbindpw-secret >/dev/null 2>&1
    fi
  fi
  rm -rf "${WORKDIR}" > /dev/null 2>&1
  echo ""
  echo "${green}[DEBUG]${reset} All cleanedup"
  echo ""
} # end cleanup

# FUNCTION - operator
operator()
{
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} OPERATOR **************${reset}"
  echo ""

  touch "${WORKDIR}/ECK"

  if [ "$(checkversion "$ECKVERSION")" -lt "$(checkversion "1.7.0")" ]; then
    echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} downloading operator: all-in-one.yaml"
    if curl -sL --fail "${ECK_DOWNLOAD_BASE}/${ECKVERSION}/all-in-one.yaml" -o all-in-one.yaml; then
      kubectl apply -f "${WORKDIR}/all-in-one.yaml" > /dev/null 2>&1
    else
      echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} Failed to get all-in-one.yaml - check network/version?"
      echo ""; help; exit 1
    fi
  else
    echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} downloading crds: crds.yaml"
    if curl -fsSL "${ECK_DOWNLOAD_BASE}/${ECKVERSION}/crds.yaml" -o crds.yaml; then
      kubectl create -f "${WORKDIR}/crds.yaml" > /dev/null 2>&1
    else
      echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} Failed to get crds.yaml - check network/version?"
      echo ""; help; exit 1
    fi
    echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} downloading operator: operator.yaml"
    if curl -fsSL "${ECK_DOWNLOAD_BASE}/${ECKVERSION}/operator.yaml" -o operator.yaml; then
      kubectl create -f "${WORKDIR}/operator.yaml" > /dev/null 2>&1
    else
      echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} Failed to get operator.yaml - check network/version?"
      echo ""; help; exit 1
    fi
  fi

  until [ "$(kubectl -n elastic-system get pod 2>/dev/null | grep elastic-operator | awk '{ print $3 }')" = "Running" ]; do
    sleep 2
  done &
  spinner $! "${blue}[DEBUG]${reset} Checking on the operator to become ready. If this does not finish in ~5 minutes something is wrong"
  echo ""
  kubectl -n elastic-system get all | sed "s/^/                     /"

  apply_trial_license

} # end operator

# FUNCTION - stackbuild
stackbuild() {
  echo ""
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} STACK ${blue}${VERSION}${green} CLUSTER ${blue}${1}${reset} **************${reset}"
  echo ""

  # create elasticsearch.yaml
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER ${blue}${1}${reset} Creating elasticsearch.yaml"
  cat >> "${WORKDIR}/elasticsearch-${1}.yaml" <<EOF
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
          command: ['sh', '-c', 'sysctl -w vm.max_map_count=1048576']
    count: 3
  http:
    service:
      spec:
        type: LoadBalancer
EOF

  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER ${blue}${1}${reset} Starting elasticsearch cluster."

  kubectl apply -f "${WORKDIR}/elasticsearch-${1}.yaml" > /dev/null 2>&1

  # checkeshealth
  checkhealth "statefulset" "${1}-es-default" "readyReplicas" "3"

  # create kibana.yaml
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER  ${blue}${1}${reset} Creating kibana.yaml"
    cat >> "${WORKDIR}/kibana-${1}.yaml" <<EOF
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

  kubectl apply -f "${WORKDIR}/kibana-${1}.yaml" > /dev/null 2>&1

  #checkkbhealth
  checkhealth "deployment" "${1}-kb" "readyReplicas" "1"

  createsummary "${1}"

} # end stackbuild

# FUNCTION - eckldap
eckldap() {

  echo "${green}[DEBUG]${reset} Adding OPENLDAP server with TLS and patching ES deployment for ldap realm"
  echo ""

  sleep 5
  echo "${green}[DEBUG]${reset} Creating patch for elasticsearch deployment(starting with this since it will take the longest)"
  cat > "${WORKDIR}/elasticsearch-eck-lab-patch.yaml" <<EOF
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
        url: "ldaps://openldap:636"
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
  kubectl patch elasticsearch eck-lab --type merge --patch-file "${WORKDIR}/elasticsearch-eck-lab-patch.yaml" >/dev/null 2>&1
  sleep 2

  echo "${green}[DEBUG]${reset} Creating ldapbindpw secret to make the keystore entry for bindpw"
  cat > "${WORKDIR}/ldapbindpw-secret.yaml" <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: ldapbindpw-secret
type: Opaque
data:
  xpack.security.authc.realms.ldap.ldap1.secure_bind_password: YWRtaW5wYXNzd29yZA==
EOF
  kubectl apply -f "${WORKDIR}/ldapbindpw-secret.yaml" >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating ca.crt and server certificate/key for openldap"
  createcerts openldap openldap-certificates

  echo "${green}[DEBUG]${reset} Creating secret for users and passwords"
  kubectl create secret generic openldap --from-literal=adminpassword=adminpassword --from-literal=users=user01,user02 --from-literal=passwords=password01,password02 >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating openldap.yaml"
  cat > "${WORKDIR}/openldap.yaml"<<EOF
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
      initContainers:
        - name: copy-certs
          image: busybox
          command: ["/bin/sh", "-c", "cp /certs-src/* /certs/"]
          volumeMounts:
            - name: openldap-certs-src
              mountPath: /certs-src
              readOnly: true
            - name: openldap-certs
              mountPath: /certs
      containers:
        - name: openldap
          image: docker.io/osixia/openldap:1.5.0
          imagePullPolicy: "IfNotPresent"
          env:
            - name: LDAP_ORGANISATION
              value: "Example Inc."
            - name: LDAP_DOMAIN
              value: "example.org"
            - name: LDAP_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  key: adminpassword
                  name: openldap
            - name: LDAP_TLS
              value: "true"
            - name: LDAP_TLS_CRT_FILENAME
              value: "openldap.crt"
            - name: LDAP_TLS_KEY_FILENAME
              value: "openldap.key"
            - name: LDAP_TLS_CA_CRT_FILENAME
              value: "ca.crt"
            - name: LDAP_TLS_VERIFY_CLIENT
              value: "never"
          volumeMounts:
            - name: openldap-certs
              mountPath: /container/service/slapd/assets/certs
          ports:
            - name: ldaps
              containerPort: 636
      volumes:
        - name: openldap-certs-src
          secret:
            secretName: openldap-certificates
            defaultMode: 0640
        - name: openldap-certs
          emptyDir: {}

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
    - name: ldaps
      port: 636
      targetPort: ldaps
  selector:
    app.kubernetes.io/name: openldap
EOF

  echo "${green}[DEBUG]${reset} Creating openldap server"
  kubectl apply -f "${WORKDIR}/openldap.yaml" >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Waiting for openldap pod to be ready"
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=openldap --timeout=120s >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Adding LDAP users"
  cat > "${WORKDIR}/users.ldif" <<'LDIF'
dn: ou=users,dc=example,dc=org
objectClass: organizationalUnit
ou: users

dn: cn=user01,ou=users,dc=example,dc=org
objectClass: inetOrgPerson
cn: user01
sn: user01
userPassword: password01
mail: user01@example.org

dn: cn=user02,ou=users,dc=example,dc=org
objectClass: inetOrgPerson
cn: user02
sn: user02
userPassword: password02
mail: user02@example.org
LDIF
  LDAP_POD=$(kubectl get pods -l app.kubernetes.io/name=openldap -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  kubectl cp "${WORKDIR}/users.ldif" "${LDAP_POD}:/tmp/users.ldif" >/dev/null 2>&1
  until kubectl exec "${LDAP_POD}" -- ldapadd -x -H ldap://localhost -D "cn=admin,dc=example,dc=org" -w adminpassword -f /tmp/users.ldif >/dev/null 2>&1; do sleep 3; done

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
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} STACK ${blue}${VERSION}${green} CLUSTER ${blue}${1}${reset} with DEDICATED masters and data nodes **************${reset}"
  echo ""

  # create elasticsearch.yaml
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER ${blue}${1}${reset} Creating elasticsearch.yaml"
  cat >> "${WORKDIR}/elasticsearch-${1}.yaml" <<EOF
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
          command: ['sh', '-c', 'sysctl -w vm.max_map_count=1048576']
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
          command: ['sh', '-c', 'sysctl -w vm.max_map_count=1048576']
    count: 3
  http:
    service:
      spec:
        type: LoadBalancer
EOF

  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER ${blue}${1}${reset} Starting elasticsearch cluster."

  kubectl apply -f "${WORKDIR}/elasticsearch-${1}.yaml" > /dev/null 2>&1

  # checkeshealth
  checkhealth "statefulset" "${1}-es-master" "readyReplicas" "3"
  checkhealth "statefulset" "${1}-es-data" "readyReplicas" "3"

  # create kibana.yaml
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER  ${blue}${1}${reset} Creating kibana.yaml"
    cat >> "${WORKDIR}/kibana-${1}.yaml" <<EOF
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

  kubectl apply -f "${WORKDIR}/kibana-${1}.yaml" > /dev/null 2>&1

  #checkkbhealth
  checkhealth "deployment" "${1}-kb" "readyReplicas" "1"

  createsummary "${1}"

} # end dedicated

# FUNCTION - beats
beats()
{
  echo ""
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} STACK ${blue}${VERSION}${green} BEATS **************${reset}"
  echo ""

  # Create and apply metricbeat-rbac
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} Creating BEATS crds"
  cat >> "${WORKDIR}/beats-crds.yaml"<<EOF
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

  kubectl apply -f "${WORKDIR}/beats-crds.yaml" > /dev/null 2>&1

  # Create and apply metricbeat-rbac
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} Creating BEATS"
  cat >> "${WORKDIR}/beats.yaml"<<EOF
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
    system.hostfs: /hostfs
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

  kubectl apply -f "${WORKDIR}/beats.yaml"  > /dev/null 2>&1

  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} filebeat, metricbeat, packetbeat, & heartbeat deployed"
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} Please wait a few minutes for the beats to become healthy. (it will restart 3-4 times before it becomes healthy) & for the data to start showing"

  echo ""

} # end beats

# FUNCTION - ecklogstash
# Deploys Logstash and beats configured to route data through Logstash → ES.
# Uses ECK Logstash CRD (ECK 2.6.0+) or falls back to a plain Deployment for older ECK.
# Beats are deployed without elasticsearchRef so ECK does not auto-wire ES output.
ecklogstash()
{
  local CLUSTER="${1}"

  echo ""
  echo "${green} ********** Deploying ECK Logstash → Beats pipeline for CLUSTER ${blue}${CLUSTER}${reset} **************${reset}"
  echo ""

  if [ "$(checkversion "$ECKVERSION")" -ge "$(checkversion "2.6.0")" ]; then
    echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} >= 2.6.0: using ECK Logstash CRD"

    if [ "$(checkversion "$VERSION")" -ge "$(checkversion "8.0.0")" ]; then
      LS_SSL_BLOCK="ssl_enabled => true\n          ssl_certificate_authorities => \"\${ECK_LAB_ES_SSL_CERTIFICATE_AUTHORITY}\""
    else
      LS_SSL_BLOCK="ssl => true\n          cacert => \"\${ECK_LAB_ES_SSL_CERTIFICATE_AUTHORITY}\""
    fi

    cat > "${WORKDIR}/logstash.yaml" <<EOF
---
apiVersion: logstash.k8s.elastic.co/v1alpha1
kind: Logstash
metadata:
  name: logstash
spec:
  version: ${VERSION}
  count: 1
  elasticsearchRefs:
  - name: ${CLUSTER}
    clusterName: eck-lab
  pipelines:
  - pipeline.id: beats-to-es
    config.string: |
      input {
        beats {
          port => 5044
        }
      }
      output {
        elasticsearch {
          hosts    => ["\${ECK_LAB_ES_HOSTS}"]
          user     => "\${ECK_LAB_ES_USER}"
          password => "\${ECK_LAB_ES_PASSWORD}"
          index    => "%{[@metadata][beat]}-%{[@metadata][version]}"
          $(echo -e "${LS_SSL_BLOCK}")
        }
      }
  services:
  - name: beats
    service:
      spec:
        type: ClusterIP
        ports:
        - port: 5044
          name: beats
          protocol: TCP
          targetPort: 5044
EOF

    kubectl apply -f "${WORKDIR}/logstash.yaml" >/dev/null 2>&1

    until [ "$(kubectl get statefulset logstash-ls 2>/dev/null | awk 'NR==2 { print $2 }')" = "1/1" ]; do
      sleep 2
    done &
    spinner $! "${blue}[DEBUG]${reset} Waiting for Logstash (ECK CRD) to become ready"
    echo ""

    LS_BEATS_HOST="logstash-ls-beats:5044"

  else
    echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} < 2.6.0: deploying Logstash as a plain Kubernetes Deployment"

    if [ "$(checkversion "$VERSION")" -ge "$(checkversion "8.0.0")" ]; then
      LS_SSL_LINE="    ssl_enabled => true"
      LS_CACERT_LINE="    ssl_certificate_authorities => [\"/usr/share/logstash/config/certs/ca.crt\"]"
    else
      LS_SSL_LINE="    ssl => true"
      LS_CACERT_LINE="    cacert => \"/usr/share/logstash/config/certs/ca.crt\""
    fi

    cat > "${WORKDIR}/logstash.yaml" <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: logstash-pipeline
data:
  logstash.conf: |
    input { beats { port => 5044 } }
    output {
      elasticsearch {
        hosts    => ["https://${CLUSTER}-es-http:9200"]
        user     => "elastic"
        password => "\${ELASTIC_PASSWORD}"
        index    => "%{[@metadata][beat]}-%{[@metadata][version]}"
${LS_SSL_LINE}
${LS_CACERT_LINE}
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: logstash
  labels:
    app: logstash
spec:
  replicas: 1
  selector:
    matchLabels:
      app: logstash
  template:
    metadata:
      labels:
        app: logstash
    spec:
      containers:
      - name: logstash
        image: docker.elastic.co/logstash/logstash:${VERSION}
        ports:
        - containerPort: 5044
          name: beats
        env:
        - name: ELASTIC_PASSWORD
          valueFrom:
            secretKeyRef:
              name: ${CLUSTER}-es-elastic-user
              key: elastic
        - name: LS_JAVA_OPTS
          value: "-Xmx512m -Xms512m"
        volumeMounts:
        - name: pipeline
          mountPath: /usr/share/logstash/pipeline
        - name: certs
          mountPath: /usr/share/logstash/config/certs
          readOnly: true
        resources:
          requests:
            memory: 1Gi
            cpu: 500m
          limits:
            memory: 1Gi
            cpu: 1
      volumes:
      - name: pipeline
        configMap:
          name: logstash-pipeline
      - name: certs
        secret:
          secretName: ${CLUSTER}-es-http-certs-public
---
apiVersion: v1
kind: Service
metadata:
  name: logstash-ls-beats
  labels:
    app: logstash
spec:
  type: ClusterIP
  selector:
    app: logstash
  ports:
  - name: beats
    port: 5044
    targetPort: 5044
    protocol: TCP
EOF

    kubectl apply -f "${WORKDIR}/logstash.yaml" >/dev/null 2>&1

    until [ "$(kubectl get deployment logstash 2>/dev/null | awk 'NR==2 { print $2 }')" = "1/1" ]; do
      sleep 2
    done &
    spinner $! "${blue}[DEBUG]${reset} Waiting for Logstash (plain Deployment) to become ready"
    echo ""

    LS_BEATS_HOST="logstash-ls-beats:5044"
  fi

  echo "${green}[DEBUG]${reset} Logstash ready. Beats will send to ${blue}${LS_BEATS_HOST}${reset}"
  echo ""

  # Deploy beats-crds (RBAC) if not already applied
  if [ ! -e "${WORKDIR}/beats-crds.yaml" ]; then
    echo "${green}[DEBUG]${reset} Creating BEATS RBAC resources"
    cat > "${WORKDIR}/beats-crds.yaml" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: metricbeat
rules:
- apiGroups: [""]
  resources: [nodes, namespaces, events, pods]
  verbs: [get, list, watch]
- apiGroups: [apps]
  resources: [statefulsets, deployments, replicasets]
  verbs: [get, list, watch]
- apiGroups: [""]
  resources: [nodes/stats]
  verbs: [get]
- nonResourceURLs: [/metrics]
  verbs: [get]
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
- apiGroups: [""]
  resources: [namespaces, pods, nodes]
  verbs: [get, watch, list]
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
    kubectl apply -f "${WORKDIR}/beats-crds.yaml" >/dev/null 2>&1
  fi

  echo "${green}[DEBUG]${reset} Deploying metricbeat and filebeat with Logstash output (${blue}${LS_BEATS_HOST}${reset})"
  cat > "${WORKDIR}/beats-logstash.yaml" <<EOF
apiVersion: beat.k8s.elastic.co/v1beta1
kind: Beat
metadata:
  name: metricbeat
spec:
  type: metricbeat
  version: ${VERSION}
  config:
    system.hostfs: /hostfs
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
        metricsets: [cpu, load, memory, network, process, process_summary]
        process:
          include_top_n:
            by_cpu: 5
            by_memory: 5
        processes: ['.*']
      - module: system
        period: 1m
        metricsets: [filesystem, fsstat]
        processors:
        - drop_event:
            when:
              regexp:
                system.filesystem.mount_point: ^/(sys|cgroup|proc|dev|etc|host|lib)(\$|/)
      - module: kubernetes
        period: 10s
        node: \${NODE_NAME}
        hosts: ["https://\${NODE_NAME}:10250"]
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        ssl:
          verification_mode: none
        metricsets: [node, system, pod, container, volume]
    processors:
    - add_cloud_metadata: {}
    - add_host_metadata: {}
    output.logstash:
      hosts: ["${LS_BEATS_HOST}"]
  daemonSet:
    podTemplate:
      spec:
        serviceAccountName: metricbeat
        automountServiceAccountToken: true
        containers:
        - args: [-e, -c, /etc/beat.yml]
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
        hostNetwork: true
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
    output.logstash:
      hosts: ["${LS_BEATS_HOST}"]
  daemonSet:
    podTemplate:
      spec:
        serviceAccountName: filebeat
        automountServiceAccountToken: true
        terminationGracePeriodSeconds: 30
        dnsPolicy: ClusterFirstWithHostNet
        hostNetwork: true
        containers:
        - name: filebeat
          securityContext:
            runAsUser: 0
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
EOF

  kubectl apply -f "${WORKDIR}/beats-logstash.yaml" >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Logstash beats deployed. Data path: beats → logstash (${blue}${LS_BEATS_HOST}${reset}) → ${CLUSTER} elasticsearch"
  echo "${green}[DEBUG]${reset} Please allow a few minutes for the beats to become healthy (they restart 3-4 times before settling)."
  echo ""

} # end ecklogstash

# FUNCTION - monitor1
monitor1()
{
  echo ""
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} STACK ${blue}${VERSION}${green} Stack Monitoring with BEATS in Pods **************${reset}"
  echo ""

  # remove labels from eck-lab-montor pods
  # is this needed?
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} Removing scrape label from monitoring pods"
  for item in $(kubectl get pods --no-headers -o custom-columns=":metadata.name" | grep eck-lab-monitor)
  do
    kubectl label pod "${item}" scrape- > /dev/null 2>&1
  done
  sleep 10

  # Create and apply monitor1.yaml
  cat >> "${WORKDIR}/monitor1.yaml"<<EOF
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

  kubectl apply -f "${WORKDIR}/monitor1.yaml" > /dev/null 2>&1

  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} Stack monitoring with BEATS in PODS deployed"
  echo ""
} # end monitor1

# FUNCTION - monitor2
monitor2()
{
  echo ""
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} STACK ${blue}${VERSION}${green} Stack Monitoring with BEATS in sidecar containers **************${reset}"
  echo ""

  # create elasticsearch-eck-lab.yaml
  echo "${green}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset} STACK ${blue}${VERSION}${reset} CLUSTER ${blue}${1}${reset} Creating elasticsearch.yaml"
  cat >> "${WORKDIR}/monitor2.yaml" <<EOF
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
          command: ['sh', '-c', 'sysctl -w vm.max_map_count=1048576']
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

  kubectl apply -f "${WORKDIR}/monitor2.yaml" > /dev/null 2>&1

  # checkkbhealth
  checkhealth "statefulset" "${1}-es-default" "readyReplicas" "3"
  checkhealth "deployment" "${1}-kb" "readyReplicas" "1"

  createsummary "${1}"
  echo ""

# notes
# you can create a normal deployment and patch it using kubectl patch kibana eck-lab --type merge -p '{"spec":{"monitoring":{"logs":{"elasticsearchRefs":[{"name":"eck-lab-monitor"}]},"metrics":{"elasticsearchRefs":[{"name":"eck-lab-monitor"}]}}}}' to change it to sidecar monitoring
#

} # end monitor2

# FUNCTION - apm
eckapm() {

  echo "${green}[DEBUG]${reset} Adding APM Server to the default stack"
  echo ""

  # ECK 3.0+ removed the ApmServer CRD. APM is now managed via Fleet/Elastic Agent APM integration.
  if [ -n "${ECKVERSION}" ] && [ "$(checkversion "$ECKVERSION")" -ge "$(checkversion "3.0.0")" ]; then
    echo "${red}[DEBUG]${reset} ECK ${blue}${ECKVERSION}${reset}: The standalone ApmServer CRD was removed in ECK 3.0."
    echo "${green}[DEBUG]${reset} For Stack 9.x / ECK 3.x, deploy APM via Fleet using the Elastic APM integration:"
    echo "${green}[DEBUG]${reset}   1. Ensure fleet is deployed (run: ./$(basename "$0") add-fleet)"
    echo "${green}[DEBUG]${reset}   2. In Kibana Fleet, add the 'Elastic APM' integration to your agent policy."
    echo "${green}[DEBUG]${reset}   3. APM Server will run inside the elastic-agent pod and be accessible on port 8200."
    exit 1
  fi
  if [ -n "${VERSION}" ] && [ "$(checkversion "$VERSION")" -ge "$(checkversion "9.0.0")" ]; then
    echo "${red}[DEBUG]${reset} Stack ${blue}${VERSION}${reset}: Standalone APM Server is not supported in 9.x."
    echo "${green}[DEBUG]${reset} Use the Fleet-managed APM integration via Elastic Agent instead."
    exit 1
  fi

  touch "${WORKDIR}/ECKAPM"

  sleep 5
  echo "${green}[DEBUG]${reset} Creating patch for kibana to install the APM assets(Fleet)"
  cat > "${WORKDIR}/kibana-eck-lab-patch.yaml" <<EOF
spec:
  config:
    xpack.fleet.packages:
    - name: apm
      version: latest
EOF

  echo "${green}[DEBUG]${reset} Applying the patch to eck-lab."
  kubectl patch kibana eck-lab --type merge --patch-file "${WORKDIR}/kibana-eck-lab-patch.yaml" >/dev/null 2>&1
  sleep 2

  echo "${green}[DEBUG]${reset} Creating apmserver.yaml"
  cat > "${WORKDIR}/apmserver.yaml"<<EOF
---
apiVersion: apm.k8s.elastic.co/v1
kind: ApmServer
metadata:
  name: ${1}
spec:
  version: ${VERSION}
  count: 1
  elasticsearchRef:
    name: "${1}"
  # this allows ECK to configure automatically the Kibana endpoint as described in https://www.elastic.co/guide/en/apm/server/current/setup-kibana-endpoint.html
  kibanaRef:
    name: "${1}"
  http:
    service:
      spec:
        type: LoadBalancer
EOF

  echo "${green}[DEBUG]${reset} Creating APM Server"
  kubectl apply -f "${WORKDIR}/apmserver.yaml" >/dev/null 2>&1

  sleep 5


  echo "${green}[DEBUG]${red} Patching kibana takes a while so please ensure that all kb pods have been recreated before trying to access APM${reset}"

  APMIP=$(wait_for_ip "${1}-apm-http" "APM Server")
  echo "${green}[DEBUG]${reset} Grabbed APM endpoint for ${1}: ${blue}https://${APMIP}:${APM_PORT}${reset}"
  echo "${1} APM endpoint: https://${APMIP}:${APM_PORT}" >> notes

} # end eckapm

# FUNCTION - fleet
fleet()
{
  echo ""
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} STACK ${blue}${VERSION}${green} Fleet Server & elastic-agent **************${reset}"
  echo ""

  # patch kibana
  echo "${green}[DEBUG]${reset} Patching kibana to set fleet settings"
  if [ "$(checkversion "$ECKVERSION")" -lt "$(checkversion "2.1.0")" ]; then
    kubectl patch kibana eck-lab --type merge -p '{"spec":{"config":{"xpack.fleet.agentPolicies":[{"is_default_fleet_server":true,"name":"Default Fleet Server on ECK policy","package_policies":[{"name":"fleet_server-1","package":{"name":"fleet_server"}}]},{"is_default":true,"name":"Default Elastic Agent on ECK policy","package_policies":[{"name":"system-1","package":{"name":"system"}},{"name":"kubernetes-1","package":{"name":"kubernetes"}}],"unenroll_timeout":900}],"xpack.fleet.agents.elasticsearch.host":"https://eck-lab-es-http.default.svc:9200","xpack.fleet.agents.fleet_server.hosts":["https://fleet-server-agent-http.default.svc:8220"],"xpack.fleet.packages":[{"name":"kubernetes","version":"latest"}]}}}'
  elif [ "$(checkversion "$ECKVERSION")" -ge "$(checkversion "2.1.0")" ]; then
    kubectl patch kibana eck-lab --type merge -p '{"spec":{"config":{"xpack.fleet.agentPolicies":[{"id":"eck-fleet-server","is_default_fleet_server":true,"monitoring_enabled":["logs","metrics"],"name":"Fleet Server on ECK policy","namespace":"default","package_policies":[{"id":"fleet_server-1","name":"fleet_server-1","package":{"name":"fleet_server"}}]},{"id":"eck-agent","is_default":true,"monitoring_enabled":["logs","metrics"],"name":"Elastic Agent on ECK policy","namespace":"default","package_policies":[{"name":"system-1","package":{"name":"system"}},{"name":"kubernetes-1","package":{"name":"kubernetes"}}],"unenroll_timeout":900}],"xpack.fleet.agents.elasticsearch.host":"https://eck-lab-es-http.default.svc:9200","xpack.fleet.agents.fleet_server.hosts":["https://fleet-server-agent-http.default.svc:8220"],"xpack.fleet.packages":[{"name":"system","version":"latest"},{"name":"elastic_agent","version":"latest"},{"name":"fleet_server","version":"latest"},{"name":"kubernetes","version":"latest"}]}}}'  > /dev/null 2>&1
  fi
  echo "${green}[DEBUG]${reset} Sleeping for 60 seconds to wait for kibana to be updated with the patch"
  sleep 60 &
  spinner $! "${blue}[DEBUG]${reset} Sleeping for 60 seconds waiting for kibana"
  echo ""

  # create fleet-server.yaml
  echo "${green}[DEBUG]${reset} Creating fleet.yaml"
  cat >> "${WORKDIR}/fleet.yaml" <<EOF
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
  # ECK 2.6+ automatically injects and trusts the ES CA cert into agents.
  # For ECK < 2.6 on Stack 7.17+ we need a bash command override to manually trust the CA.
  if [ "$(checkversion "$VERSION")" -ge "$(checkversion "7.17.0")" ] && [ "$(checkversion "$ECKVERSION")" -lt "$(checkversion "2.6.0")" ]; then
    # ECK < 2.6: use bash workaround to manually copy CA cert into trust store
    cat >> "${WORKDIR}/fleet.yaml" <<EOF
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
        serviceAccountName: fleet-server
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
    # ECK 2.6+: CA cert trust is handled automatically by ECK; no bash override needed
    cat >> "${WORKDIR}/fleet.yaml" <<EOF
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
        serviceAccountName: fleet-server
        automountServiceAccountToken: true
        securityContext:
          runAsUser: 0
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
EOF
  fi

  echo "${green}[DEBUG]${reset} STACK VERSION: ${blue}${VERSION}${reset} Starting fleet-server & elastic-agents."

  kubectl apply -f "${WORKDIR}/fleet.yaml" > /dev/null 2>&1

  # checkfleethealth
  #checkhealth "agent" "elastic-agent"
  sleep 30 &
  spinner $! "${blue}[DEBUG]${reset} Sleeping for 30 seconds waiting for fleet"

  # get fleet url
  unset FLEETIP
  while [ "${FLEETIP}" = "" ] || [ "${FLEETIP}" = "<pending>" ]
  do
    FLEETIP=$(kubectl get service | grep fleet-server-agent-http | awk '{ print $4 }')
    echo "${green}[DEBUG]${reset} Grabbing Fleet Server endpoint (external): ${blue}https://${FLEETIP}:8220${reset}"
    sleep 3
  done
  echo "${1} Fleet Server endpoint: https://${FLEETIP}:8220" >> notes



  # for Fleet Server 8.2+ - Add external output with fingerprint and verification_mode
  if [ "$(checkversion "$VERSION")" -ge "$(checkversion "8.2.0")" ]; then

    echo "${green}[DEBUG]${reset} Waiting 30 seconds for fleet server to calm down to set the external output"
    sleep 30 &
    spinner $! "${blue}[DEBUG]${reset} Sleeping for 30 seconds waiting for fleet server"

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
    FINGERPRINT=$(openssl x509 -fingerprint -sha256 -noout -in "${WORKDIR}/ca.crt" | awk -F'=' '{ print $2 }' | sed 's/://g')

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
    EXTID=$(curl -s -k -u "elastic:${PASSWORD}" https://${KIBANAIP}:5601/api/fleet/outputs | jq -r '.items[]| select(.name=="external")|.id')


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
  if [ "$(checkversion "$VERSION")" -ge "$(checkversion "8.0.0")" ] && [ "$(checkversion "$VERSION")" -lt "$(checkversion "8.2.0")" ]; then

    echo "${green}[DEBUG]${reset} Waiting 30 seconds for fleet server to calm down to set the output"
    sleep 30 &
    spinner $! "${blue}[DEBUG]${reset} Sleeping for 30 seconds waiting for fleet server"

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
  touch "${WORKDIR}/HELM"

  echo ""
  echo "${green} ********** Deploying ELASTIC STACK ${blue}${VERSION}${green} with HELM CHARTS - without ECK operator **************${reset}"
  echo ""

  # add helm repo and update it
  helm_add_elastic_repo

  # Create elastic users password and create secret
  echo "${green}[DEBUG]${reset} Create elastic user password and create a secret"
  PASSWORD=$(openssl rand -base64 29 | tr -d "=+/" | cut -c1-25)
  kubectl create secret generic elastic-credentials --from-literal=password="${PASSWORD}" --from-literal=username=elastic >/dev/null 2>&1

  # Create certificates
  echo "${green}[DEBUG]${reset} Create certificates for the stack and add create secrets"
  createcerts "${1}-es-default" elastic-certificates
  createcerts "${1}-kb-default" kibana-certificates

  # Create es-values.yaml
  echo "${green}[DEBUG]${reset} Create es-values.yaml"
  cat > "${WORKDIR}/es-values.yaml" <<EOF
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
  helm upgrade --install elasticsearch elastic/elasticsearch --version "$(getchartversion "${VERSION}")" -f "${WORKDIR}/es-values.yaml" --set imageTag="${VERSION}" >/dev/null 2>&1

  checkhealth "statefulset" "${1}-es-default" "readyReplicas" "3"
  echo ""

  # start kibana

  # create encryptionkey and its secret
  echo "${green}[DEBUG]${reset} Creating kibana encryption key secret"
  encryptionkey=$(openssl rand -base64 29 | tr -d "=+/" | cut -c1-32)
  kubectl create secret generic kibana-encryptionkey --from-literal=encryptionkey="${encryptionkey}" >/dev/null 2>&1

  # Create kb-values.yaml
  echo "${green}[DEBUG]${reset} Create kb-vaules.yaml"
  cat > "${WORKDIR}/kb-values.yaml" <<EOF
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
  helm upgrade --install "${1}-kb" elastic/kibana --version "$(getchartversion "${VERSION}" kibana)" -f "${WORKDIR}/kb-values.yaml" --set imageTag="${VERSION}" >/dev/null 2>&1

  checkhealth "deployment" "${1}-kb-kibana" "readyReplicas" "1"
  echo ""


  createsummary "${1}"

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
  cat > "${WORKDIR}/es-override.yaml" <<EOF
esConfig:
  elasticsearch.yml: |
    xpack.security.authc.realms.ldap.ldap1:
      order: 0
      url: "ldaps://openldap:636"
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
  helm upgrade elasticsearch elastic/elasticsearch --version "$(getchartversion "${VERSION}")" -f "${WORKDIR}/es-values.yaml" -f "${WORKDIR}/es-override.yaml" --set imageTag="${VERSION}" >/dev/null 2>&1
  sleep 2

  echo "${green}[DEBUG]${reset} Creating ldapbindpw secret to make the keystore entry for bindpw"
  cat > "${WORKDIR}/ldapbindpw-secret.yaml" <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: ldapbindpw-secret
type: Opaque
data:
  xpack.security.authc.realms.ldap.ldap1.secure_bind_password: YWRtaW5wYXNzd29yZA==
EOF
  kubectl apply -f "${WORKDIR}/ldapbindpw-secret.yaml" >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating ca.crt and server certificate/key for openldap"
  createcerts openldap openldap-certificates

  echo "${green}[DEBUG]${reset} Creating secret for users and passwords"
  kubectl create secret generic openldap --from-literal=adminpassword=adminpassword --from-literal=users=user01,user02 --from-literal=passwords=password01,password02 >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating openldap.yaml"
  cat > "${WORKDIR}/openldap.yaml"<<EOF
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
      initContainers:
        - name: copy-certs
          image: busybox
          command: ["/bin/sh", "-c", "cp /certs-src/* /certs/"]
          volumeMounts:
            - name: openldap-certs-src
              mountPath: /certs-src
              readOnly: true
            - name: openldap-certs
              mountPath: /certs
      containers:
        - name: openldap
          image: docker.io/osixia/openldap:1.5.0
          imagePullPolicy: "IfNotPresent"
          env:
            - name: LDAP_ORGANISATION
              value: "Example Inc."
            - name: LDAP_DOMAIN
              value: "example.org"
            - name: LDAP_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  key: adminpassword
                  name: openldap
            - name: LDAP_TLS
              value: "true"
            - name: LDAP_TLS_CRT_FILENAME
              value: "openldap.crt"
            - name: LDAP_TLS_KEY_FILENAME
              value: "openldap.key"
            - name: LDAP_TLS_CA_CRT_FILENAME
              value: "ca.crt"
            - name: LDAP_TLS_VERIFY_CLIENT
              value: "never"
          volumeMounts:
            - name: openldap-certs
              mountPath: /container/service/slapd/assets/certs
          ports:
            - name: ldaps
              containerPort: 636
      volumes:
        - name: openldap-certs-src
          secret:
            secretName: openldap-certificates
            defaultMode: 0640
        - name: openldap-certs
          emptyDir: {}

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
    - name: ldaps
      port: 636
      targetPort: ldaps
  selector:
    app.kubernetes.io/name: openldap
EOF

  echo "${green}[DEBUG]${reset} Creating openldap server"
  kubectl apply -f "${WORKDIR}/openldap.yaml" >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Waiting for openldap pod to be ready"
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=openldap --timeout=120s >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Adding LDAP users"
  cat > "${WORKDIR}/users.ldif" <<'LDIF'
dn: ou=users,dc=example,dc=org
objectClass: organizationalUnit
ou: users

dn: cn=user01,ou=users,dc=example,dc=org
objectClass: inetOrgPerson
cn: user01
sn: user01
userPassword: password01
mail: user01@example.org

dn: cn=user02,ou=users,dc=example,dc=org
objectClass: inetOrgPerson
cn: user02
sn: user02
userPassword: password02
mail: user02@example.org
LDIF
  LDAP_POD=$(kubectl get pods -l app.kubernetes.io/name=openldap -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  kubectl cp "${WORKDIR}/users.ldif" "${LDAP_POD}:/tmp/users.ldif" >/dev/null 2>&1
  until kubectl exec "${LDAP_POD}" -- ldapadd -x -H ldap://localhost -D "cn=admin,dc=example,dc=org" -w adminpassword -f /tmp/users.ldif >/dev/null 2>&1; do sleep 3; done

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
  cat > "${WORKDIR}/fb-values.yaml" <<EOF
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
  helm upgrade --install "${1}-fb" elastic/filebeat --version "$(getchartversion "${VERSION}" filebeat)" -f "${WORKDIR}/fb-values.yaml" --set imageTag="${VERSION}" >/dev/null 2>&1

  checkhealth "daemonset" "${1}-fb-filebeat" "numberReady" "3"

  echo ""
  echo "${green}[DEBUG]${reset} Deploying metricbeat via helm"

  echo "${green}[DEBUG]${reset} Adding ${blue}prometheus-community${reset} repository as pre-req"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1
  helm repo update >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Create kube_state_metrics"
  helm upgrade --install kube-state-metrics prometheus-community/kube-state-metrics >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating mb-values.yaml"
  cat > "${WORKDIR}/mb-values.yaml" <<EOF
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
  helm upgrade --install "${1}-mb" elastic/metricbeat --version "$(getchartversion "${VERSION}" metricbeat)" -f "${WORKDIR}/mb-values.yaml" --set imageTag="${VERSION}" >/dev/null 2>&1

  checkhealth "daemonset" "${1}-mb-metricbeat" "numberReady" "3"

} # end helmbeats

# FUNCTION - helmlogstash
helmlogstash() {

  echo "${green}[DEBUG]${reset} Deploying logstash via helm"

  echo "${green}[DEBUG]${reset} Creating ls-values.yaml"
  cat > "${WORKDIR}/ls-values.yaml" <<EOF
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
  helm upgrade --install "${1}-ls" elastic/logstash --version "$(getchartversion "${VERSION}" logstash)" -f "${WORKDIR}/ls-values.yaml" --set imageTag="${VERSION}" >/dev/null 2>&1

  checkhealth "statefulset" "${1}-ls-logstash" "readyReplicas" "1"

} # end helmlogstash

# FUNCTION - helmlsbeats
helmlsbeats() {

  beatsetup "filebeat"
  beatsetup "metricbeat"

  echo ""
  echo "${green}[DEBUG]${reset} Deploying filebeat via helm for logstash output"

  echo "${green}[DEBUG]${reset} Creating fb-values.yaml"
  cat > "${WORKDIR}/fb-values.yaml" <<EOF
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
  helm upgrade --install "${1}-fb" elastic/filebeat --version "$(getchartversion "${VERSION}" filebeat)" -f "${WORKDIR}/fb-values.yaml" --set imageTag="${VERSION}" >/dev/null 2>&1

  checkhealth "daemonset" "${1}-fb-filebeat" "numberReady" "3"

  echo ""
  echo "${green}[DEBUG]${reset} Deploying metricbeat via helm"

  echo "${green}[DEBUG]${reset} Adding ${blue}prometheus-community${reset} repository as pre-req"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1
  helm repo update >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Create kube_state_metrics"
  helm upgrade --install kube-state-metrics prometheus-community/kube-state-metrics >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating mb-values.yaml"
  cat > "${WORKDIR}/mb-values.yaml" <<EOF
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
  helm upgrade --install "${1}-mb" elastic/metricbeat --version "$(getchartversion "${VERSION}" metricbeat)" -f "${WORKDIR}/mb-values.yaml" --set imageTag="${VERSION}" >/dev/null 2>&1

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
  cat > "${WORKDIR}/mb-values.yaml" <<EOF
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
  helm upgrade --install "${1}-mb" elastic/metricbeat --version "$(getchartversion "${VERSION}" metricbeat)" -f "${WORKDIR}/mb-values.yaml" --set imageTag="${VERSION}" >/dev/null 2>&1

  checkhealth "deployment" "${1}-mb-metricbeat-metrics" "readyReplicas" "1"

} # end helmmonitor

# FUNCTION - nativestack
nativestack()
{
  touch "${WORKDIR}/NATIVE"

  echo ""
  echo "${green} ********** Deploying ELASTIC STACK ${blue}${VERSION}${green} Natively without helm or operator **************${reset}"
  echo ""

  # Create elastic users password and create secret
  echo "${green}[DEBUG]${reset} Create elastic user password and create a secret"
  PASSWORD=$(openssl rand -base64 29 | tr -d "=+/" | cut -c1-25)
  kubectl create secret generic elastic-credentials --from-literal=password="${PASSWORD}" --from-literal=username=elastic >/dev/null 2>&1

  # Create certificates
  echo "${green}[DEBUG]${reset} Create certificates for the stack and add create secrets"
  createcerts "${1}-es-default" elastic-certificates
  createcerts "${1}-kb-default" kibana-certificates

  # Create elasticsearch.yaml
  echo "${green}[DEBUG]${reset} Create elasticsearch.yaml"
  cat > "${WORKDIR}/elasticsearch.yaml" <<EOF
---
# Source: elasticsearch/templates/poddisruptionbudget.yaml
apiVersion: policy/v1
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
        command: ["sysctl", "-w", "vm.max_map_count=1048576"]
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
  if [ "$(checkversion "${VERSION}")" -lt "$(checkversion "8.0.0")" ]; then
    cat >> "${WORKDIR}/elasticsearch.yaml" <<EOF
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
  elif [ "$(checkversion "${VERSION}")" -ge "$(checkversion "8.0.0")" ]; then
    cat >> "${WORKDIR}/elasticsearch.yaml" <<EOF
          - name: node.roles
            value: "master,data,data_content,data_hot,data_warm,data_cold,ingest,ml,remote_cluster_client,transform,"
EOF
  fi
  cat >> "${WORKDIR}/elasticsearch.yaml" <<EOF
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
  kubectl apply -f "${WORKDIR}/elasticsearch.yaml" >/dev/null 2>&1

  checkhealth "statefulset" "${1}-default" "readyReplicas" "3"
  sleep 5
  echo ""

  # get ESIP
  unset ESIP
  while [ "${ESIP}" = "" ] || [ "${ESIP}" = "<pending>" ]
  do
    ESIP=$(kubectl get service | grep "${1}-default" | grep -v headless | awk '{ print $4 }')
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
  if [ "$(checkversion "$VERSION")" -lt "$(checkversion "7.8.0")" ]; then
    until curl -k -s -X POST -u "elastic:${PASSWORD}" "https://${ESIP}:9200/_security/user/kibana/_password" -H "Content-Type: application/json" -d "{\"password\": \"${PASSWORD}\"}" | grep -q "^{}"; do sleep 10; done;
    kubectl create secret generic kibana-credentials --from-literal=password="${PASSWORD}" --from-literal=username=kibana >/dev/null 2>&1
  elif [ "$(checkversion "$VERSION")" -gt "$(checkversion "7.8.0")" ]; then
    until curl -k -s -X POST -u "elastic:${PASSWORD}" "https://${ESIP}:9200/_security/user/kibana_system/_password" -H "Content-Type: application/json" -d "{\"password\": \"${PASSWORD}\"}" | grep -q "^{}"; do sleep 10; done;
    kubectl create secret generic kibana-credentials --from-literal=password="${PASSWORD}" --from-literal=username=kibana_system >/dev/null 2>&1
  fi

  # create encryptionkey and its secret
  echo "${green}[DEBUG]${reset} Creating kibana encryption key secret"
  encryptionkey=$(openssl rand -base64 29 | tr -d "=+/" | cut -c1-32)
  kubectl create secret generic kibana-encryptionkey --from-literal=encryptionkey="${encryptionkey}" >/dev/null 2>&1

  # Create kibana.yaml
  echo "${green}[DEBUG]${reset} Create kibana.yaml"
  cat > "${WORKDIR}/kibana.yaml" <<EOF
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
  if [ "$(checkversion "${VERSION}")" -ge "$(checkversion "7.7.0")" ]; then
    cat >> "${WORKDIR}/kibana.yaml" <<EOF
    xpack.encryptedSavedObjects.encryptionKey: \${KIBANA_ENCRYPTION_KEY}
EOF
  fi
  cat >> "${WORKDIR}/kibana.yaml" <<EOF
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
  kubectl apply -f "${WORKDIR}/kibana.yaml" >/dev/null 2>&1

  checkhealth "deployment" "${1}-kibana" "readyReplicas" "1"
  echo ""

  createsummary "${1}"

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
  if [ "$(checkversion "${VERSION}")" -gt "$(checkversion "7.6.0")" ]; then
    until curl -k -s -X POST -u "elastic:${PASSWORD}" "https://${ESIP}:9200/_security/user/beats_user" -H "Content-Type: application/json" -d "{\"username\":\"beats_user\",\"roles\":[\"beats_role\",\"beats_admin\",\"ingest_admin\",\"monitoring_user\",\"remote_monitoring_agent\",\"remote_monitoring_collector\",\"kibana_system\",\"kibana_admin\"],\"full_name\":\"beats_user\",\"email\":null,\"metadata\":{},\"enabled\":true,\"password\":\"${PASSWORD}\"}" >/dev/null 2>&1
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
  kubectl create secret generic beats-credentials --from-literal=password="${PASSWORD}" --from-literal=username=beats_user >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating filebeat-kubernetes.yaml"
  cat > "${WORKDIR}/filebeat-kubernetes.yaml" <<EOF
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
  kubectl apply -f "${WORKDIR}/filebeat-kubernetes.yaml"

  checkhealth "daemonset" "${1}-fb" "numberReady" "3"

  echo ""
  echo "${green}[DEBUG]${reset} Deploying metricbeat via kubernetes"

  echo "${green}[DEBUG]${reset} Cloning and starting kube-state-metrics"
  git clone https://github.com/kubernetes/kube-state-metrics.git "${WORKDIR}/kube-state-metrics" >/dev/null 2>&1
  find "${WORKDIR}/kube-state-metrics"/examples/standard -type f -print0 | xargs -0 sed -i '' -e 's/kube-system/default/g' >/dev/null 2>&1
  kubectl apply -f "${WORKDIR}/kube-state-metrics/examples/standard"

  echo "${green}[DEBUG]${reset} Creating metricbeat-kubernetes.yaml"
  cat > "${WORKDIR}/metricbeat-kubernetes.yaml" <<EOF
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
    system.hostfs: /hostfs
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
  kubectl apply -f "${WORKDIR}/metricbeat-kubernetes.yaml" >/dev/null 2>&1

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
  if [ "$(checkversion "${VERSION}")" -gt "$(checkversion "7.6.0")" ]; then
    until curl -k -s -X POST -u "elastic:${PASSWORD}" "https://${ESIP}:9200/_security/user/beats_user" -H "Content-Type: application/json" -d "{\"username\":\"beats_user\",\"roles\":[\"beats_role\",\"beats_admin\",\"ingest_admin\",\"monitoring_user\",\"remote_monitoring_agent\",\"remote_monitoring_collector\",\"kibana_system\",\"kibana_admin\"],\"full_name\":\"beats_user\",\"email\":null,\"metadata\":{},\"enabled\":true,\"password\":\"${PASSWORD}\"}" >/dev/null 2>&1
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
  kubectl create secret generic beats-credentials --from-literal=password="${PASSWORD}" --from-literal=username=beats_user >/dev/null 2>&1

  echo "${green}[DEBUG]${reset}Creating metricbeat-kubernetes.yaml"
  cat > "${WORKDIR}/metricbeat-kubernetes.yaml" <<EOF
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
    system.hostfs: /hostfs
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

  if [ "$(checkversion "$VERSION")" -ge "$(checkversion "7.5.0")" ] && [ "$(checkversion "$VERSION")" -lt "$(checkversion "7.9.0")" ]; then
    echo "${es78}" >> "${WORKDIR}/metricbeat-kubernetes.yaml"
  elif [ "$(checkversion "$VERSION")" -lt "$(checkversion "7.5.0")" ]; then
    echo "${es74}" >> "${WORKDIR}/metricbeat-kubernetes.yaml"
  else
    # 7.9+ and 8.x: same metricsets as 7.5-7.9 range
    echo "${es78}" >> "${WORKDIR}/metricbeat-kubernetes.yaml"
  fi

  cat >> "${WORKDIR}/metricbeat-kubernetes.yaml" <<EOF
      xpack.enabled: true
      period: 10s
EOF
  if [ "$(checkversion "$VERSION")" -lt "$(checkversion "7.9.0")" ]; then
    cat >> "${WORKDIR}/metricbeat-kubernetes.yaml" <<EOF
      hosts: ["https://native-lab-default-0.native-lab-default-headless.default.svc.cluster.local:9200", "https://native-lab-default-1.native-lab-default-headless.default.svc.cluster.local:9200", "https://native-lab-default-2.native-lab-default-headless.default.svc.cluster.local:9200"]
EOF
  else
    cat >> "${WORKDIR}/metricbeat-kubernetes.yaml" <<EOF
      hosts: ["https://\${ELASTICSEARCH_HOST}:9200"]
      scope: cluster
EOF
  fi
  cat >> "${WORKDIR}/metricbeat-kubernetes.yaml" <<EOF
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
        ]
        env:
        - name: ELASTICSEARCH_HOST
          value: native-lab-default
        - name: ELASTICSEARCH_PORT
          value: "9200"
EOF
  if [ "$(checkversion "${VERSION}")" -lt "$(checkversion "8.0.0")" ]; then
    cat >> "${WORKDIR}/metricbeat-kubernetes.yaml" <<EOF
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
    cat >> "${WORKDIR}/metricbeat-kubernetes.yaml" <<EOF
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
  cat >> "${WORKDIR}/metricbeat-kubernetes.yaml" <<EOF
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
  kubectl apply -f "${WORKDIR}/metricbeat-kubernetes.yaml" >/dev/null 2>&1

  checkhealth "deployment" "native-lab-mb" "readyReplicas" "1"

} # end nativemonitor

#############################################################
# FUNCTIONS - STACK CONFIG POLICY, FLEET NON-ROOT, STANDALONE AGENT
#############################################################

# FUNCTION - eckstackpolicy
# Creates a basic StackConfigPolicy for all ES clusters in the namespace (requires ECK 2.6.0+)
eckstackpolicy() {
  echo ""
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} StackConfigPolicy **************${reset}"
  echo ""

  if [ "$(checkversion "$ECKVERSION")" -lt "$(checkversion "2.6.0")" ]; then
    echo "${red}[DEBUG]${reset} StackConfigPolicy requires ECK 2.6.0+. Current ECK: ${blue}${ECKVERSION}${reset}"
    echo ""; help; exit 1
  fi

  echo "${green}[DEBUG]${reset} Creating stack-policy.yaml"
  cat > "${WORKDIR}/stack-policy.yaml" <<EOF
apiVersion: stackconfigpolicy.k8s.elastic.co/v1alpha1
kind: StackConfigPolicy
metadata:
  name: eck-lab-stack-policy
  namespace: default
spec:
  resourceSelector:
    matchLabels: {}
  elasticsearch:
    config:
      logger.level: INFO
      xpack.security.authc.api_key.enabled: "true"
    clusterSettings:
      persistent:
        indices.recovery.max_bytes_per_sec: "100mb"
        cluster.routing.allocation.enable: "all"
    indexTemplates:
      composableIndexTemplates:
        lab-logs-template:
          index_patterns:
          - "lab-logs-*"
          template:
            settings:
              number_of_shards: 1
              number_of_replicas: 1
          priority: 100
          _meta:
            description: "Lab index template managed by StackConfigPolicy"
EOF

  echo "${green}[DEBUG]${reset} Applying StackConfigPolicy"
  kubectl apply -f "${WORKDIR}/stack-policy.yaml" >/dev/null 2>&1
  echo "${green}[DEBUG]${reset} StackConfigPolicy ${blue}eck-lab-stack-policy${reset} applied."
  echo "${green}[DEBUG]${reset} Check status: ${blue}kubectl get stackconfigpolicy eck-lab-stack-policy${reset}"
  echo ""
} # end eckstackpolicy

# FUNCTION - fleet_nonroot
# Deploys fleet-server and elastic-agent via ECK Agent CRDs running as non-root (requires ECK 2.6.0+)
fleet_nonroot() {
  echo ""
  echo "${green} ********** Deploying ECK ${blue}${ECKVERSION}${green} STACK ${blue}${VERSION}${green} Fleet Server & elastic-agent (NON-ROOT) **************${reset}"
  echo ""

  if [ "$(checkversion "$ECKVERSION")" -lt "$(checkversion "2.6.0")" ]; then
    echo "${red}[DEBUG]${reset} Non-root fleet requires ECK 2.6.0+ (automatic CA cert injection for non-root). Current ECK: ${blue}${ECKVERSION}${reset}"
    echo ""; help; exit 1
  fi

  if [ -e "${WORKDIR}/fleet.yaml" ]; then
    echo "${red}[DEBUG]${reset} fleet.yaml already exists (root fleet deployed). Run cleanup first."
    exit 1
  fi

  echo "${green}[DEBUG]${reset} Patching kibana to configure Fleet settings"
  kubectl patch kibana eck-lab --type merge -p '{"spec":{"config":{"xpack.fleet.agentPolicies":[{"id":"eck-fleet-server","is_default_fleet_server":true,"monitoring_enabled":["logs","metrics"],"name":"Fleet Server on ECK policy","namespace":"default","package_policies":[{"id":"fleet_server-1","name":"fleet_server-1","package":{"name":"fleet_server"}}]},{"id":"eck-agent","is_default":true,"monitoring_enabled":["logs","metrics"],"name":"Elastic Agent on ECK policy","namespace":"default","package_policies":[{"name":"system-1","package":{"name":"system"}},{"name":"kubernetes-1","package":{"name":"kubernetes"}}],"unenroll_timeout":900}],"xpack.fleet.agents.elasticsearch.host":"https://eck-lab-es-http.default.svc:9200","xpack.fleet.agents.fleet_server.hosts":["https://fleet-server-agent-http.default.svc:8220"],"xpack.fleet.packages":[{"name":"system","version":"latest"},{"name":"elastic_agent","version":"latest"},{"name":"fleet_server","version":"latest"},{"name":"kubernetes","version":"latest"}]}}}' >/dev/null 2>&1
  sleep 60 &
  spinner $! "${blue}[DEBUG]${reset} Sleeping for 60 seconds waiting for kibana fleet config"
  echo ""

  echo "${green}[DEBUG]${reset} Creating fleet-nonroot.yaml"
  cat >> "${WORKDIR}/fleet-nonroot.yaml" <<EOF
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
        serviceAccountName: fleet-server
        automountServiceAccountToken: true
        securityContext:
          runAsUser: 1000
          runAsGroup: 1000
          fsGroup: 1000
          runAsNonRoot: true
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
          runAsUser: 1000
          runAsGroup: 1000
          fsGroup: 1000
          runAsNonRoot: true
EOF

  echo "${green}[DEBUG]${reset} Starting fleet-server & elastic-agents (non-root)."
  kubectl apply -f "${WORKDIR}/fleet-nonroot.yaml" >/dev/null 2>&1

  sleep 30 &
  spinner $! "${blue}[DEBUG]${reset} Sleeping for 30 seconds waiting for fleet"
  echo ""

  unset FLEETIP
  while [ "${FLEETIP}" = "" ] || [ "${FLEETIP}" = "<pending>" ]; do
    FLEETIP=$(kubectl get service 2>/dev/null | grep fleet-server-agent-http | awk '{ print $4 }')
    echo "${green}[DEBUG]${reset} Grabbing Fleet Server endpoint: ${blue}https://${FLEETIP}:8220${reset}"
    sleep 3
  done
  echo "${1} Fleet Server (non-root) endpoint: https://${FLEETIP}:8220" >> notes

  if [ "$(checkversion "$VERSION")" -ge "$(checkversion "8.2.0")" ]; then
    sleep 30 &
    spinner $! "${blue}[DEBUG]${reset} Sleeping for 30 seconds waiting for fleet server to settle"
    echo ""

    generate_post_data()
    {
      cat <<EOF
{"fleet_server_hosts":["https://${FLEETIP}:8220","https://fleet-server-agent-http.default.svc:8220"]}
EOF
    }
    curl -k -u "elastic:${PASSWORD}" -X PUT "https://${KIBANAIP}:5601/api/fleet/settings" \
      --header 'kbn-xsrf: true' --header 'Content-Type: application/json' \
      -d "$(generate_post_data)" >/dev/null 2>&1
    sleep 10

    FINGERPRINT=$(openssl x509 -fingerprint -sha256 -noout -in "${WORKDIR}/ca.crt" | awk -F'=' '{ print $2 }' | sed 's/://g')
    generate_post_data()
    {
      cat <<EOF
{"name":"external","type":"elasticsearch","hosts":["https://${ESIP}:9200"],"is_default":false,"is_default_monitoring":false,"ca_trusted_fingerprint":"${FINGERPRINT}","config_yaml":"ssl:\n  verification_mode: none"}
EOF
    }
    curl -k -u "elastic:${PASSWORD}" -X POST "https://${KIBANAIP}:5601/api/fleet/outputs" \
      --header 'kbn-xsrf: true' --header 'Content-Type: application/json' \
      -d "$(generate_post_data)" >/dev/null 2>&1
    sleep 10

    EXTID=$(curl -s -k -u "elastic:${PASSWORD}" "https://${KIBANAIP}:5601/api/fleet/outputs" | jq -r '.items[]| select(.name=="external")|.id')
    generate_post_data()
    {
      cat <<EOF
{"name":"External Agent Policy","description":"For elastic-agent from outside the k8s cluster","namespace":"default","monitoring_enabled":["logs","metrics"],"data_output_id":"${EXTID}","monitoring_output_id":"${EXTID}"}
EOF
    }
    curl -k -u "elastic:${PASSWORD}" -X POST "https://${KIBANAIP}:5601/api/fleet/agent_policies?sys_monitoring=true" \
      --header 'kbn-xsrf: true' --header 'Content-Type: application/json' \
      -d "$(generate_post_data)" >/dev/null 2>&1
    sleep 10
    echo "${green}[DEBUG]${reset} External output created for agents outside the k8s cluster."
    echo "${green}[DEBUG]${reset} Please use https://${FLEETIP}:8220 with --insecure to register elastic-agent from outside the cluster."
  fi
} # end fleet_nonroot

# FUNCTION - agent_standalone
# Deploy standalone elastic-agent (no ECK Agent CRD) as Deployment or DaemonSet, enrolled with Fleet
# Usage: agent_standalone <deploy|ds> <root|nonroot>
agent_standalone() {
  local DEPLOY_TYPE="${1}"  # deploy or ds
  local RUN_MODE="${2}"     # root or nonroot

  local RUN_USER=0
  local FILENAME_SUFFIX="${DEPLOY_TYPE}"
  local SEC_CTX_EXTRA=""
  local DEPLOY_LABEL="DEPLOYMENT"
  [ "${DEPLOY_TYPE}" = "ds" ] && DEPLOY_LABEL="DAEMONSET"

  if [ "${RUN_MODE}" = "nonroot" ]; then
    RUN_USER=1000
    FILENAME_SUFFIX="${DEPLOY_TYPE}-nonroot"
    SEC_CTX_EXTRA="        runAsGroup: 1000
        fsGroup: 1000
        runAsNonRoot: true"
  fi

  local YAML_FILE="${WORKDIR}/agent-standalone-${FILENAME_SUFFIX}.yaml"
  local SECRET_NAME="agent-enroll-token-${FILENAME_SUFFIX}"

  echo ""
  echo "${green} ********** Deploying standalone elastic-agent ${blue}${VERSION}${green} as ${blue}${DEPLOY_LABEL}${green} (${blue}${RUN_MODE}${green}, no ECK CRD) **************${reset}"
  echo ""

  if [ ! -e "${WORKDIR}/fleet.yaml" ] && [ ! -e "${WORKDIR}/fleet-nonroot.yaml" ]; then
    echo "${red}[DEBUG]${reset} No Fleet Server deployment found. Run add-fleet or add-fleet-nonroot first."
    exit 1
  fi

  echo "${green}[DEBUG]${reset} Getting default elastic-agent policy ID from Fleet"
  local AGENT_POLICY_ID="" ENROLL_TOKEN="" c=0
  while [ -z "${AGENT_POLICY_ID}" ] || [ "${AGENT_POLICY_ID}" = "null" ]; do
    AGENT_POLICY_ID=$(curl -s -k -u "elastic:${PASSWORD}" \
      "https://${KIBANAIP}:5601/api/fleet/agent_policies" \
      -H 'kbn-xsrf: true' 2>/dev/null | \
      jq -r '.items[] | select(.is_default == true) | .id // empty' | head -1)
    sleep 3
    ((c++))
    if [ "${c}" -ge 20 ]; then
      echo "${red}[DEBUG]${reset} Could not get default elastic-agent policy ID after 60 seconds."
      exit 1
    fi
  done
  echo "${green}[DEBUG]${reset} Got policy ID: ${blue}${AGENT_POLICY_ID}${reset}"

  c=0
  while [ -z "${ENROLL_TOKEN}" ] || [ "${ENROLL_TOKEN}" = "null" ]; do
    ENROLL_TOKEN=$(curl -s -k -u "elastic:${PASSWORD}" \
      "https://${KIBANAIP}:5601/api/fleet/enrollment_api_keys?policy_id=${AGENT_POLICY_ID}" \
      -H 'kbn-xsrf: true' 2>/dev/null | \
      jq -r '.items[] | select(.active == true) | .api_key // empty' | head -1)
    sleep 3
    ((c++))
    if [ "${c}" -ge 20 ]; then
      echo "${red}[DEBUG]${reset} Could not get enrollment token after 60 seconds."
      exit 1
    fi
  done
  echo "${green}[DEBUG]${reset} Got enrollment token."

  kubectl create secret generic "${SECRET_NAME}" \
    --from-literal=token="${ENROLL_TOKEN}" >/dev/null 2>&1

  echo "${green}[DEBUG]${reset} Creating ${YAML_FILE}"
  cat > "${YAML_FILE}" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: elastic-agent-standalone
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: elastic-agent-standalone
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
- apiGroups: ["apps"]
  resources:
  - statefulsets
  - deployments
  - replicasets
  verbs:
  - get
  - list
  - watch
- apiGroups: [""]
  resources:
  - nodes/stats
  verbs:
  - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: elastic-agent-standalone
subjects:
- kind: ServiceAccount
  name: elastic-agent-standalone
  namespace: default
roleRef:
  kind: ClusterRole
  name: elastic-agent-standalone
  apiGroup: rbac.authorization.k8s.io
EOF

  if [ "${DEPLOY_TYPE}" = "deploy" ]; then
    cat >> "${YAML_FILE}" <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: elastic-agent-standalone-${FILENAME_SUFFIX}
  namespace: default
  labels:
    app: elastic-agent-standalone-${FILENAME_SUFFIX}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: elastic-agent-standalone-${FILENAME_SUFFIX}
  template:
    metadata:
      labels:
        app: elastic-agent-standalone-${FILENAME_SUFFIX}
    spec:
      serviceAccountName: elastic-agent-standalone
      automountServiceAccountToken: true
      securityContext:
        runAsUser: ${RUN_USER}
${SEC_CTX_EXTRA}
      containers:
      - name: elastic-agent
        image: docker.elastic.co/beats/elastic-agent:${VERSION}
        env:
        - name: FLEET_URL
          value: "https://fleet-server-agent-http.default.svc:8220"
        - name: FLEET_ENROLLMENT_TOKEN
          valueFrom:
            secretKeyRef:
              name: ${SECRET_NAME}
              key: token
        - name: FLEET_INSECURE
          value: "true"
        resources:
          requests:
            memory: 400Mi
            cpu: 100m
          limits:
            memory: 600Mi
            cpu: 500m
EOF
  else
    cat >> "${YAML_FILE}" <<EOF
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: elastic-agent-standalone-${FILENAME_SUFFIX}
  namespace: default
  labels:
    app: elastic-agent-standalone-${FILENAME_SUFFIX}
spec:
  selector:
    matchLabels:
      app: elastic-agent-standalone-${FILENAME_SUFFIX}
  template:
    metadata:
      labels:
        app: elastic-agent-standalone-${FILENAME_SUFFIX}
    spec:
      serviceAccountName: elastic-agent-standalone
      automountServiceAccountToken: true
      securityContext:
        runAsUser: ${RUN_USER}
${SEC_CTX_EXTRA}
      containers:
      - name: elastic-agent
        image: docker.elastic.co/beats/elastic-agent:${VERSION}
        env:
        - name: FLEET_URL
          value: "https://fleet-server-agent-http.default.svc:8220"
        - name: FLEET_ENROLLMENT_TOKEN
          valueFrom:
            secretKeyRef:
              name: ${SECRET_NAME}
              key: token
        - name: FLEET_INSECURE
          value: "true"
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        resources:
          requests:
            memory: 400Mi
            cpu: 100m
          limits:
            memory: 600Mi
            cpu: 500m
        volumeMounts:
        - name: proc
          mountPath: /hostfs/proc
          readOnly: true
        - name: sys
          mountPath: /hostfs/sys
          readOnly: true
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      - key: node-role.kubernetes.io/control-plane
        effect: NoSchedule
      volumes:
      - name: proc
        hostPath:
          path: /proc
      - name: sys
        hostPath:
          path: /sys
EOF
  fi

  echo "${green}[DEBUG]${reset} Applying standalone elastic-agent ${DEPLOY_TYPE} (${RUN_MODE})"
  kubectl apply -f "${YAML_FILE}" >/dev/null 2>&1

  if [ "${DEPLOY_TYPE}" = "deploy" ]; then
    local DEPLOY_NAME="elastic-agent-standalone-${FILENAME_SUFFIX}"
    until [ "$(kubectl get deployment "${DEPLOY_NAME}" -ojson 2>/dev/null | jq -r '.status.readyReplicas // 0')" = "1" ]; do
      sleep 2
    done &
    spinner $! "${blue}[DEBUG]${reset} Waiting for ${DEPLOY_NAME} to become ready"
    echo ""
  fi
  echo "${green}[DEBUG]${reset} Standalone elastic-agent ${DEPLOY_LABEL} (${RUN_MODE}) deployed successfully."
  echo ""
} # end agent_standalone

#############################################################
# MAIN SCRIPT
#############################################################


case ${1} in
  operator)
    check_prerequisites
    choose_eckversion "1.4.0"
    checkdir
    operator
    ;;
  build|start|stack|eck)
    check_prerequisites
    choose_eckversion "1.4.0"
    choose_stackversion "7.10.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    checkdir
    operator
    stackbuild "eck-lab"
    summary
    ;;
  helmeck)
    check_prerequisites helm
    choose_eckversion "2.0.0"
    choose_stackversion "7.10.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    checkdir
    echo "${VERSION}" > "${WORKDIR}/VERSION"
    helmeck_operator
    helmeck_stackbuild "eck-lab"
    summary
    ;;
  eckldap)
    check_prerequisites
    choose_eckversion "1.4.0"
    choose_stackversion "7.10.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    checkdir
    operator
    stackbuild "eck-lab"
    eckldap
    summary
    ;;
  dedicated)
    check_prerequisites
    choose_eckversion "1.4.0"
    choose_stackversion "7.10.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    checkdir
    operator
    dedicated "eck-lab"
    summary
    ;;
  beats|beat)
    check_prerequisites
    choose_eckversion "1.4.0"
    choose_stackversion "7.10.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    checkdir
    operator
    stackbuild "eck-lab"
    beats "eck-lab"
    summary
    ;;
  monitor1)
    check_prerequisites
    choose_eckversion "1.4.0"
    choose_stackversion "7.10.0"
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
    check_prerequisites
    choose_eckversion "1.7.0"
    choose_stackversion "7.14.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    checkdir
    operator
    stackbuild "eck-lab-monitor"
    monitor2 "eck-lab"
    summary
    ;;
  eckapm)
    check_prerequisites
    choose_eckversion "1.4.0" "3.0.0"
    choose_stackversion "7.10.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    checkdir
    operator
    stackbuild "eck-lab"
    eckapm "eck-lab"
    summary
    ;;
  fleet)
    check_prerequisites
    choose_eckversion "1.7.0"
    choose_stackversion "7.14.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    checkdir
    operator
    stackbuild "eck-lab"
    fleet "eck-lab"
    summary
    ;;
  stackpolicy|stack-policy)
    check_prerequisites
    choose_eckversion "2.6.0"
    choose_stackversion "7.10.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    checkdir
    operator
    stackbuild "eck-lab"
    eckstackpolicy
    summary
    ;;
  fleet-nonroot)
    check_prerequisites
    choose_eckversion "2.6.0"
    choose_stackversion "7.14.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkrequiredversion
    checkdir
    operator
    stackbuild "eck-lab"
    fleet_nonroot "eck-lab"
    summary
    ;;
  helm)
    check_prerequisites helm
    choose_stackversion_noeck "7.14.0" "7"
    checkrequiredversionhelm
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    helmstack "helm-lab"
    summary
    ;;
  helmldap)
    check_prerequisites helm
    choose_stackversion_noeck "7.14.0" "7"
    checkrequiredversionhelm
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    helmstack "helm-lab"
    helmldap "helm-lab"
    summary
    ;;
  helmbeats)
    check_prerequisites helm
    choose_stackversion_noeck "7.14.0" "7"
    checkrequiredversionhelm
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    helmstack "helm-lab"
    helmbeats "helm-lab"
    summary
    ;;
  helmlogstashbeats)
    check_prerequisites helm
    choose_stackversion_noeck "7.14.0" "7"
    checkrequiredversionhelm
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    helmstack "helm-lab"
    helmlogstash "helm-lab"
    helmlsbeats "helm-lab"
    summary
    ;;
  helmmonitor)
    check_prerequisites helm
    choose_stackversion_noeck "7.14.0" "7"
    checkrequiredversionhelm
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    helmstack "helm-lab"
    helmmonitor "helm-lab"
    summary
    ;;
  native)
    check_prerequisites
    choose_stackversion_noeck "7.3.0" "8"
    checkrequiredversionnative "7.3.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    nativestack "native-lab"
    summary
    ;;
  nativebeats)
    check_prerequisites
    choose_stackversion_noeck "7.3.0" "8"
    checkrequiredversionnative "7.3.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    nativestack "native-lab"
    nativebeats "native-lab"
    summary
    ;;
  nativemonitor)
    check_prerequisites
    choose_stackversion_noeck "7.5.0" "8"
    checkrequiredversionnative "7.5.0"
    checkcontainerimage "docker.elastic.co/elasticsearch/elasticsearch:${VERSION}"
    checkdir
    nativestack "native-lab"
    nativemonitor "native-lab"
    summary
    ;;
  add-ldap)
    check_prerequisites
    loadstate
    checkexistingdeployment "any"
    if [ -e "${WORKDIR}/ECK" ] || [ -e "${WORKDIR}/HELMECK" ]; then
      eckldap
    elif [ -e "${WORKDIR}/HELM" ]; then
      helmldap "helm-lab"
    else
      echo "${red}[DEBUG]${reset} add-ldap is not supported for native deployments."
      exit 1
    fi
    ;;
  add-beats)
    check_prerequisites
    loadstate
    checkexistingdeployment "any"
    if [ -e "${WORKDIR}/ECK" ] || [ -e "${WORKDIR}/HELMECK" ]; then
      beats "eck-lab"
    elif [ -e "${WORKDIR}/HELM" ]; then
      helmbeats "helm-lab"
    elif [ -e "${WORKDIR}/NATIVE" ]; then
      nativebeats "native-lab"
    fi
    ;;
  add-monitor1)
    check_prerequisites
    loadstate
    checkexistingdeployment "eck"
    # Warn if monitor2 sidecar mode is already active on eck-lab
    if kubectl get elasticsearch eck-lab -o json 2>/dev/null | jq -e '((.spec.monitoring.metrics.elasticsearchRefs // []) | length) > 0' >/dev/null 2>&1; then
      echo "${red}[WARN]${reset} eck-lab already has sidecar (monitor2) monitoring configured."
      echo "${red}[WARN]${reset} Running monitor1 (beats-in-pods) on top will create duplicate monitoring data."
      echo "${red}[WARN]${reset} Consider running cleanup and choosing one mode only."
      echo ""
    fi
    # Only create the monitoring cluster if it does not already exist
    if kubectl get elasticsearch eck-lab-monitor >/dev/null 2>&1; then
      echo "${green}[DEBUG]${reset} Monitoring cluster ${blue}eck-lab-monitor${reset} already exists, skipping creation."
    else
      stackbuild "eck-lab-monitor"
    fi
    monitor1 "eck-lab"
    summary
    ;;
  add-monitor2)
    check_prerequisites
    loadstate
    checkexistingdeployment "eck"
    if [ "$(checkversion "$ECKVERSION")" -lt "$(checkversion "1.7.0")" ] || [ "$(checkversion "$VERSION")" -lt "$(checkversion "7.14.0")" ]; then
      echo "${red}[DEBUG]${reset} Sidecar stack monitoring requires ECK 1.7.0+ & Stack 7.14.0+."
      echo ""
      help
      exit 1
    fi
    # Warn if monitor1 beats-pods mode is already active
    if [ -e "${WORKDIR}/monitor1.yaml" ]; then
      echo "${red}[WARN]${reset} monitor1 (beats-in-pods) was already deployed."
      echo "${red}[WARN]${reset} Running monitor2 (sidecar) on top will create duplicate monitoring data."
      echo "${red}[WARN]${reset} Consider removing monitor1 beats first: kubectl delete -f ${WORKDIR}/monitor1.yaml"
      echo ""
    fi
    # Only create the monitoring cluster if it does not already exist
    if kubectl get elasticsearch eck-lab-monitor >/dev/null 2>&1; then
      echo "${green}[DEBUG]${reset} Monitoring cluster ${blue}eck-lab-monitor${reset} already exists, skipping creation."
    else
      stackbuild "eck-lab-monitor"
    fi
    # For the addon case, patch the existing eck-lab resources to add sidecar monitoring
    # instead of regenerating the entire manifest (which is what monitor2() does for fresh deploys)
    echo "${green}[DEBUG]${reset} Patching ${blue}eck-lab${reset} Elasticsearch to enable sidecar monitoring"
    kubectl patch elasticsearch eck-lab --type merge -p \
      '{"spec":{"monitoring":{"metrics":{"elasticsearchRefs":[{"name":"eck-lab-monitor"}]},"logs":{"elasticsearchRefs":[{"name":"eck-lab-monitor"}]}}}}' >/dev/null 2>&1
    echo "${green}[DEBUG]${reset} Patching ${blue}eck-lab${reset} Kibana to enable sidecar monitoring"
    kubectl patch kibana eck-lab --type merge -p \
      '{"spec":{"monitoring":{"metrics":{"elasticsearchRefs":[{"name":"eck-lab-monitor"}]},"logs":{"elasticsearchRefs":[{"name":"eck-lab-monitor"}]}}}}' >/dev/null 2>&1
    echo "${green}[DEBUG]${reset} Sidecar monitoring patch applied. ECK will rolling-restart eck-lab pods to inject sidecars."
    echo "${green}[DEBUG]${reset} This may take several minutes. Watch progress with: ${blue}kubectl get pods -w${reset}"
    checkhealth "statefulset" "eck-lab-es-default" "readyReplicas" "3"
    checkhealth "deployment" "eck-lab-kb" "readyReplicas" "1"
    summary
    ;;
  add-fleet)
    check_prerequisites
    loadstate
    checkexistingdeployment "eck"
    if [ "$(checkversion "$ECKVERSION")" -lt "$(checkversion "1.7.0")" ] || [ "$(checkversion "$VERSION")" -lt "$(checkversion "7.14.0")" ]; then
      echo "${red}[DEBUG]${reset} Fleet Server requires ECK 1.7.0+ & Stack 7.14.0+."
      echo ""
      help
      exit 1
    fi
    fleet "eck-lab"
    summary
    ;;
  add-apm)
    check_prerequisites
    loadstate
    checkexistingdeployment "eck"
    eckapm "eck-lab"
    summary
    ;;
  add-logstash)
    check_prerequisites
    loadstate
    checkexistingdeployment "any"
    if [ -e "${WORKDIR}/beats.yaml" ]; then
      echo "${red}[WARN]${reset} Direct-to-ES beats (beats.yaml) are already deployed."
      echo "${red}[WARN]${reset} Running add-logstash will deploy ADDITIONAL beats configured for Logstash output."
      echo "${red}[WARN]${reset} To avoid duplicate collection, remove direct beats first:"
      echo "${red}[WARN]${reset}   kubectl delete -f ${WORKDIR}/beats.yaml && kubectl delete -f ${WORKDIR}/beats-crds.yaml"
      echo ""
    fi
    if [ -e "${WORKDIR}/beats-logstash.yaml" ]; then
      echo "${red}[DEBUG]${reset} Logstash beats (beats-logstash.yaml) are already deployed. Use cleanup first."
      exit 1
    fi
    if [ -e "${WORKDIR}/ECK" ] || [ -e "${WORKDIR}/HELMECK" ]; then
      ecklogstash "eck-lab"
    elif [ -e "${WORKDIR}/HELM" ]; then
      checkhelm
      helmlogstash "helm-lab"
      helmlsbeats "helm-lab"
    else
      echo "${red}[DEBUG]${reset} add-logstash is not supported for native deployments."
      exit 1
    fi
    ;;
  add-stack-policy)
    check_prerequisites
    loadstate
    checkexistingdeployment "eck"
    eckstackpolicy
    ;;
  add-fleet-nonroot)
    check_prerequisites
    loadstate
    checkexistingdeployment "eck"
    if [ "$(checkversion "$ECKVERSION")" -lt "$(checkversion "2.6.0")" ] || [ "$(checkversion "$VERSION")" -lt "$(checkversion "7.14.0")" ]; then
      echo "${red}[DEBUG]${reset} add-fleet-nonroot requires ECK 2.6.0+ and Stack 7.14.0+."
      echo ""; help; exit 1
    fi
    fleet_nonroot "eck-lab"
    summary
    ;;
  add-agent-deploy)
    check_prerequisites
    loadstate
    checkexistingdeployment "eck"
    agent_standalone "deploy" "root"
    ;;
  add-agent-ds)
    check_prerequisites
    loadstate
    checkexistingdeployment "eck"
    agent_standalone "ds" "root"
    ;;
  add-agent-deploy-nonroot)
    check_prerequisites
    loadstate
    checkexistingdeployment "eck"
    agent_standalone "deploy" "nonroot"
    ;;
  add-agent-ds-nonroot)
    check_prerequisites
    loadstate
    checkexistingdeployment "eck"
    agent_standalone "ds" "nonroot"
    ;;
  cleanup|clean|teardown|stop)
    cleanup
    exit 1
    ;;
  info|summary|detail)
    if [ -e "${WORKDIR}/VERSION" ]; then
      VERSION=$(cat "${WORKDIR}/VERSION" 2>/dev/null)
      ECKVERSION=$(cat "${WORKDIR}/ECKVERSION" 2>/dev/null)
    fi
    summary
    ;;
  *)
    help
    exit 1
    ;;
esac
