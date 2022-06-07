#!/bin/bash

source ./conjur.config

# This script deletes running instances and brings up 
#   an initialized Conjur Follower & (optionally) a CLI node.

CURR_IP=$(ifconfig ens160 | grep "inet " | awk '{print $2}')
if [[ "$CURR_IP" != "$CONJUR_FOLLOWER_HOST_IP" ]]; then
  echo "Edit CONJUR_FOLLOWER_HOST_IP value in conjur.config to $CURR_IP."
  exit -1
fi

LEADER_OK=$(curl -sk $CONJUR_APPLIANCE_URL/health | jq .ok)
if [[ "$LEADER_OK" != "true" ]]; then
  echo "Leader ping failed. Check value of CONJUR_LEADER_HOSTNAME and"
  echo "  CONJUR_LEADER_HOST_IP in conjur.config."
  exit -1
fi

#################
main() {
  teardown_follower
  if [[ "$1" == "stop" ]]; then
    exit -1
  fi
  #configure_networking
  follower_up
}

#################
teardown_follower() {
  echo "Terminating any running Follower container..."
  $DOCKER stop $CONJUR_FOLLOWER_CONTAINER_NAME > /dev/null 2>&1
  $DOCKER rm $CONJUR_FOLLOWER_CONTAINER_NAME > /dev/null 2>&1
}

#################
configure_networking() {
  # enable IPV4 port forwarding
  sysctl -w net.ipv4.ip_forward=1
  # update local firewall rules to allow container-container connections
  firewall-cmd --permanent --zone=public --add-rich-rule='rule family=ipv4 source address=172.17.0.0/16 accept'
  firewall-cmd --reload
}

############################
follower_up() {
  # Bring up Conjur Follower node
  $DOCKER run -d					\
    --name $CONJUR_FOLLOWER_CONTAINER_NAME		\
    --label role=conjur_node				\
    -p "$CONJUR_FOLLOWER_PORT:443"			\
    -e "CONJUR_AUTHENTICATORS=$CONJUR_AUTHENTICATORS"	\
    --restart unless-stopped				\
    --security-opt seccomp=unconfined			\
    $CONJUR_APPLIANCE_IMAGE

  if $NO_DNS; then
    # add entry to follower's /etc/hosts so $CONJUR_LEADER_HOSTNAME resolves
    $DOCKER exec -it $CONJUR_FOLLOWER_CONTAINER_NAME \
	bash -c "echo \"$CONJUR_LEADER_HOST_IP $CONJUR_LEADER_HOSTNAME\" >> /etc/hosts"
  fi

  echo "Initializing Conjur Follower"
  cat $FOLLOWER_SEED_FILE 				\
  | $DOCKER exec -i $CONJUR_FOLLOWER_CONTAINER_NAME	\
		evoke unpack seed -
  $DOCKER exec $CONJUR_FOLLOWER_CONTAINER_NAME 		\
		evoke configure follower -p $CONJUR_LEADER_PORT

  echo "Follower configured."
}

main "$@"
