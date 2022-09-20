#!/bin/sh

# shell script to run for GCP environments
# to finish off compute installs

# create a flag file and check for it
if [ -f /ran_startup ]; then
  exit;
fi

# if OS is RHEL based
if [[ `cat /etc/os-release | grep ^ID` =~ "centos" ]] || [[ `cat /etc/os-release | grep ^ID` =~ "rhel" ]] || [[ `cat /etc/os-release | grep ^ID` =~ "rocky" ]]; then
  # disable selinux
  sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux
  setenforce Permissive

  # create elasticsearch repo
  rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
  cat >> /etc/yum.repos.d/elasticsearch.repo<<EOF
[elasticsearch-7]
name=Elasticsearch repository for 7.x packages
baseurl=https://artifacts.elastic.co/packages/7.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md

[elasticsearch-8]
name=Elasticsearch repository for 8.x packages
baseurl=https://artifacts.elastic.co/packages/8.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
EOF

  # install epel repository
  yum install epel-release -y

  # install packages
  yum install unzip bind-utils openssl vim-enhanced bash-completion git wget nmap bc jq bash-completion-extras docker-compose kubectl -y

  # disable services
  for service in auditd firewalld mdmonitor postfix
  do
    systemctl disable ${service}
  done

  # install docker
  # will just grab the script but not install docker to save time
  curl -fsSL https://get.docker.com -o /usr/local/bin/get-docker.sh
  # sh /tmp/get-docker.sh
  # systemctl daemon-reload
  # systemctl enable docker
  # systemctl start docker

  # updating vm.max_map_count
  cat >> /etc/sysctl.d/20-elastic.conf<<EOF
vm.max_map_count = 262144
EOF

  # install some of my scripts
  curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/deploy-elastic.sh -o /usr/local/bin/deploy-elastic.sh
  curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/deploy-elastick8s.sh -o /usr/local/bin/deploy-elastick8s.sh
  curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/kube.sh -o /usr/local/bin/kube.sh
  chmod +x /usr/local/bin/*.sh

  #yum update -y
elif [[ `cat /etc/os-release | grep ^ID` =~ "debian" ]] || [[ `cat /etc/os-release | grep ^ID` =~ "ubuntu" ]]; then

  # install packages
  apt-get update
  apt-get install unzip openssl bash-completion git wget nmap bc jq docker-compose kubectl -y

  # add elasticsearch repo
  wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
  apt-get install apt-transport-https -y
  echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | tee -a /etc/apt/sources.list.d/elastic-7.x.list
  echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" | tee -a /etc/apt/sources.list.d/elastic-8.x.list
  apt-get update

  # disable services
  for service in apparmor ufw
  do
    systemctl disable ${service}
  done

  # updating vm.max_map_count
  cat >> /etc/sysctl.d/20-elastic.conf<<EOF
vm.max_map_count = 262144
EOF

  # install some of my scripts
  curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/deploy-elastic.sh -o /usr/local/bin/deploy-elastic.sh
  curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/deploy-elastick8s.sh -o /usr/local/bin/deploy-elastick8s.sh
  curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/kube.sh -o /usr/local/bin/kube.sh
  chmod +x /usr/local/bin/*.sh
fi

  echo "done" > /ran_startup
  reboot