#!/bin/bash

set -e

# get port number
running_zoo_containers=$(docker ps | grep zoo)
if [ -z "$running_zoo_containers" ]; then
  echo "Error: No ZooKeeper containers found. Please ensure the ZooKeeper container is running."
  exit 1
fi
zookeeper_port=$(echo "$running_zoo_containers" | grep -oP '0.0.0.0:\K(21[0-9]{2,})' | head -n 1)

# get auth digest
zk_readwrites=$(docker exec frc-directors-director bash -c 'echo $FOUND_ZK_READWRITE')
zk_password=$(echo "$zk_readwrites" | tr -d '\r\n' | sed 's/^root://')
if [ -z "$zk_password" ]; then
  echo "Error: Could not fetch or clean the FOUND_ZK_READWRITE variable!"
  exit 1
fi
zk_auth_string="root:$zk_password"

# get list of deployments
raw_output=$(docker exec -i frc-zookeeper-servers-zookeeper ./elastic_cloud_apps/zookeeper/bin/zkCli.sh -server "localhost:$zookeeper_port" 2>/dev/null <<EOF
addauth digest "$zk_auth_string"
ls /v1/clusters
quit
EOF
)
deployment_ids=$(echo "$raw_output" | grep '^\[' | grep -v 'zk:' | tr -d '[]' | tr ',' ' ')
if [ -z "$deployment_ids" ]; then
  echo "No deployment IDs found or failed to retrieve them from ZooKeeper."
  exit 1
fi

# list deployments
for deployment_id in $deployment_ids; do
  deployment_info=$(docker exec -i frc-zookeeper-servers-zookeeper ./elastic_cloud_apps/zookeeper/bin/zkCli.sh -server "localhost:$zookeeper_port" 2>/dev/null <<EOF
addauth digest "$zk_auth_string"
get /v1/clusters/$deployment_id
quit
EOF
)

  deployment_name=$(echo "$deployment_info" | grep -oP '"data":{"name":"\K[^"]+')
  if [ -n "$deployment_name" ]; then
    echo "$deployment_id - $deployment_name"
  else
    echo "$deployment_id - (Name not found)"
  fi
done
