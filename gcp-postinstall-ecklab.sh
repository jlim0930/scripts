#!/bin/sh

# shell script to run for GCP environments
# to finish off compute installs


if [ -z "$SCRIPT" ]
then 
    script /tmp/post-install.txt /bin/sh -c "$0 $*"
    exit 0
fi

# check for a flag and exit
if [ -f /ran_startup ]; then
  exit;
fi

function distro() {
  if [ -f /etc/os-release ]; then
    source /etc/os-release
    echo $ID
  else
    uname
  fi
}


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
yum --enablerepo=extras install epel-release -y

# install docker repo
yum config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# install packages
yum install unzip bind-utils openssl vim-enhanced bash-completion git wget nmap bc jq net-tools kubectl docker-ce docker-ce-cli containerd.io -y

# enable docker
for u in $(lid -g -n google-sudoers); do usermod -a -G docker $u; done

systemctl daemon-reload
systemctl enable docker
systemctl start docker

# install gui
yum groupinstall base-x xfce-desktop -y
yum install xrdp firefox -y

echo "exec xfce4-session" >> /etc/xrdp/xrdp.ini

systemctl daemon-reload
systemctl enable xrdp
systemctl start xrdp

# disable services
for service in auditd firewalld mdmonitor postfix bluetooth 
do
  systemctl disable ${service}
done


# install some scripts for lab
curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/deploy-elastick8s.sh -o /usr/local/bin/deploy-elastick8s.sh
curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/kube-ecklab.sh -o /usr/local/bin/kube.sh
chmod +x /usr/local/bin/*.sh

yum update -y




echo "done" > /ran_startup
reboot

