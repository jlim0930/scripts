#!/usr/bin/env bash

# This scrip will create a CA cert and key and a wildcard cert

# CONFIG
COUNTRY="US" # COUNTY
STATE="TX" # STATE
LOCALITY="AUSTIN" # LOCALITY
ORGANIZATION="HOME" # ORGANIZATION NAME
ORGANIZATIONUNIT="LIM" # ORGANIZATION UNIT
COMMONNAME="device" # COMMON NAME
SAN="DNS.1 = *.lim.home
DNS.2 = localhost
IP.1 = 127.0.0.1
IP.2 = 192.168.1.1
IP.3 = 192.168.1.2
IP.4 = 192.168.1.3
IP.5 = 192.168.1.4
IP.6 = 192.168.1.5
IP.7 = 192.168.1.10
IP.8 = 192.168.1.254
IP.9 = 192.168.1.253
IP.10 = 192.168.1.252"


# Do not change anything below

# set -x


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NAME=${1:-localhost}
SUBJECT="/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${ORGANIZATION}/OU=${ORGANIZATIONUNIT}/CN=${COMMONNAME}"

# Create CA Key
CA_KEY=${DIR}/ca.key
PASS=`openssl rand -base64 48`
echo ${PASS} > ${DIR}/ca.passphrase
[ ! -f ${CA_KEY} ] || rm -rf ${CA_KEY}
openssl genrsa -des3 -passout pass:${PASS} -out ${CA_KEY}

# Create non Crypt CA Key
CA_NONCRYPT_KEY=${DIR}/ca.noncrypt.key
openssl rsa -passin pass:${PASS} -in ${CA_KEY} -out ${CA_NONCRYPT_KEY}

# Create CA Cert
CA_CERT=${DIR}/ca.crt
[ -f ${CA_CERT} ] ||  rm -rf ${CA_CERT}
openssl req -x509 -new -nodes -key ${CA_KEY} -sha256 -days 3650 -passin pass:${PASS} -out ${CA_CERT} -subj ${SUBJECT}
#openssl req -x509 -new -nodes -key ${CA_NONCRYPT_KEY} -sha256 -days 365 -out ${CA_CERT} -subj ${SUBJECT}

# Create wildcard key
WILD_KEY=${DIR}/wildcard.key
[ -f ${WILD_KEY} ] || rm -rf ${WILD_KEY}
openssl genrsa -out ${WILD_KEY} 2048

# Create wildcard CSR
CSRCONFIG=${DIR}/csrconfig.cnf
WILD_CSR=wildcard.csr
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
${SAN}
EOF
openssl req -new -newkey rsa:2048 -key ${WILD_KEY} -nodes -out ${WILD_CSR} -extensions v3_req -config ${CSRCONFIG}
rm -rf ${CSRCONFIG}

# Sign wildcard cert
CERTCONFIG=${DIR}/certconfig.cnf
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
${SAN}
EOF
openssl x509 -req -in ${WILD_CSR} -CA ${CA_CERT} -CAkey ${CA_KEY} -passin pass:${PASS} -CAcreateserial -out ${WILD_CERT} -days 3650 -sha256 -extfile ${CERTCONFIG} -extensions req_ext
#openssl x509 -req -in ${WILD_CSR} -CA ${CA_CERT} -CAkey ${CA_NONCRYPT_KEY} -CAcreateserial -out ${WILD_CERT} -days 365 -sha256 -extfile ${CERTCONFIG} -extensions req_ext
rm -rf ${CERTCONFIG}

# check cert
openssl x509 -text -in ${WILD_CERT}

[ -f ${WILD_KEY} ] || rm -rf ${WILD_KEY}
openssl genrsa -out ${WILD_KEY} 2048

# Create wildcard CSR
CSRCONFIG=${DIR}/csrconfig.cnf
WILD_CSR=wildcard.csr
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
${SAN}
EOF
openssl req -new -newkey rsa:2048 -key ${WILD_KEY} -nodes -out ${WILD_CSR} -extensions v3_req -config ${CSRCONFIG}
rm -rf ${CSRCONFIG}

# Sign wildcard cert
CERTCONFIG=${DIR}/certconfig.cnf
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
${SAN}
EOF
openssl x509 -req -in ${WILD_CSR} -CA ${CA_CERT} -CAkey ${CA_KEY} -passin pass:${PASS} -CAcreateserial -out ${WILD_CERT} -days 3650 -sha256 -extfile ${CERTCONFIG} -extensions req_ext
#openssl x509 -req -in ${WILD_CSR} -CA ${CA_CERT} -CAkey ${CA_NONCRYPT_KEY} -CAcreateserial -out ${WILD_CERT} -days 365 -sha256 -extfile ${CERTCONFIG} -extensions req_ext
rm -rf ${CERTCONFIG}

# check cert
openssl x509 -text -in ${WILD_CERT}

