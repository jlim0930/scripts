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


# make /etc/hosts entry
cat >> /etc/hosts <<EOF
192.168.49.170 kibana.eck.lab
EOF

# enable fast mirror
cat > /etc/dnf/dnf.conf <<EOF
[main]
gpgcheck=1
installonly_limit=3
clean_requirements_on_remove=True
best=False
skip_if_unavailable=True
ip_resolve=4
fastestmirror=1
EOF

yum clean all
yum makecache

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

# install helm
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# install some scripts for lab
curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/deploy-elastick8s.sh -o /usr/local/bin/deploy-elastick8s.sh
curl -fsSL https://raw.githubusercontent.com/jlim0930/scripts/master/kube-ecklab.sh -o /usr/local/bin/kube.sh
chmod +x /usr/local/bin/*.sh

yum update -y




echo "done" > /ran_startup
reboot

