#!/usr/bin/env bash

# This scrip will create a CA cert and key and a wildcard cert

# CONFIG
COUNTRY="US" # COUNTY
STATE="TX" # STATE
LOCALITY="AUSTIN" # LOCALITY
ORGANIZATION="WORK" # ORGANIZATION NAME
ORGANIZATIONUNIT="IT" # ORGANIZATION UNIT
COMMONNAME="SERVER" # COMMON NAME
DNS1="*.work.it" # domain name


# Do not change anything below

set -x


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NAME=${1:-localhost}
SUBJECT="/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${ORGANIZATION}/OU=${ORGANIZATIONUNIT}/CN=${COMMONNAME}"

# Create CA Key
CA_KEY=${DIR}/CA.key
PASS=`openssl rand -base64 48`
echo ${PASS} > ${DIR}/CA.passphrase
[ ! -f ${CA_KEY} ] || rm -rf ${CA_KEY}
openssl genrsa -des3 -passout pass:${PASS} -out ${CA_KEY}

# Create non Crypt CA Key
CA_NONCRYPT_KEY=${DIR}/CA.noncrypt.key
openssl rsa -passin pass:${PASS} -in ${CA_KEY} -out ${CA_NONCRYPT_KEY}

# Create CA Cert
CA_CERT=${DIR}/CA.crt
[ -f ${CA_CERT} ] ||  rm -rf ${CA_CERT}
openssl req -x509 -new -nodes -key ${CA_KEY} -sha256 -days 365 -passin pass:${PASS} -out ${CA_CERT} -subj ${SUBJECT}
#openssl req -x509 -new -nodes -key ${CA_NONCRYPT_KEY} -sha256 -days 365 -out ${CA_CERT} -subj ${SUBJECT}

# Create wildcard key
WILD_KEY=${DIR}/wildcard.key.pem
[ -f ${WILD_KEY} ] || rm -rf ${WILD_KEY}
openssl genrsa -out ${WILD_KEY} 2048

# Create wildcard CSR
CSRCONFIG=/tmp/csrconfig.cnf
WILD_CSR=wildcard.csr
PASS2=`openssl rand -base64 48`
[ ! -f ${CSRCONFIG} ] || rm -rf ${CSRCONFIG}
cat > ${CSRCONFIG}<<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no
[req_distinguished_name]
C  =  ${COUNTRY}
ST  =  ${STATE}
L  =  ${LOCALITY}
O  =  ${ORGANIZATION}
OU  =  ${ORGANIZATIONUNIT}
CN  =  ${COMMONNAME}
[v3_req]
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${DNS1}
EOF
openssl req -new -newkey rsa:2048 -key ${WILD_KEY} -nodes -out ${WILD_CSR} -extensions v3_req -config ${CSRCONFIG}
rm -rf ${CSRCONFIG}

# Sign wildcard cert
CERTCONFIG=/tmp/certconfig.cnf
WILD_CERT=${DIR}/wildcard.crt
[ ! -f ${CERTCONFIG} ] || rm -rf ${CERTCONFIG}
cat > ${CERTCONFIG}<<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
[req_ext]
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DNS1}
EOF
openssl x509 -req -in ${WILD_CSR} -CA ${CA_CERT} -CAkey ${CA_KEY} -passin pass:${PASS} -CAcreateserial -out ${WILD_CERT} -days 365 -sha256 -extfile ${CERTCONFIG} -extensions req_ext
#openssl x509 -req -in ${WILD_CSR} -CA ${CA_CERT} -CAkey ${CA_NONCRYPT_KEY} -CAcreateserial -out ${WILD_CERT} -days 365 -sha256 -extfile ${CERTCONFIG} -extensions req_ext
rm -rf ${CERTCONFIG}

# check cert
openssl x509 -text -in ${WILD_CERT}
