#!/bin/sh

# shell script to run for GCP environments
# to finish off compute installs

# create a flag file and check for it
if [ -f /ran_startup ]; then
  exit;
fi

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
yum install bash-completion git wget nmap bc -y

# disable services
for service in auditd firewalld mdmonitor postfix
do
  systemctl disable ${service}
done

# install docker
curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
sh /tmp/get-docker.sh
systemctl daemon-reload
systemctl enable docker
systemctl start docker

# updating vm.max_map_count
cat >> /etc/sysctl.d/20-elastic.conf<<EOF
vm.max_map_count = 262144
EOF

# install some of my scripts
curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/deploy-elastic.sh -o /usr/local/bin/deploy-elastic.sh
curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/kube.sh -o /usr/local/bin/kube.sh
chmod +x /usr/local/bin/*.sh

# update packages and reboot - updating packages is taking super long so turning off for now
#yum update -y
echo 'done' > /ran_startup
reboot
