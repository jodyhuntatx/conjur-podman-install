#!/bin/bash

source ./conjur.config

export CONJUR_AUTHN_LOGIN=admin
export CONJUR_AUTHN_API_KEY=$CONJUR_ADMIN_PASSWORD

# This script deletes running instances and brings up 
#   initialized Conjur Leader & CLI nodes.

#################
main() {
#  teardown_conjur
  if [[ "$1" == "stop" ]]; then
    exit -1
  fi
  #configure_networking
#  leader_up
  cli_config
  load_demo_policy
  echo
  echo
  echo "Performing smoke test secret retrieval from Leader:"
  echo -n "DB username: "
  $CYBR conjur get-secret -i secrets/db-username 
  echo
  echo -n "DB password: "
  $CYBR conjur get-secret -i secrets/db-password
  echo
}

#################
teardown_conjur() {
  echo "Terminating running Leader container..."
  $DOCKER stop $CONJUR_LEADER_CONTAINER_NAME
  $DOCKER rm $CONJUR_LEADER_CONTAINER_NAME
}

#################
configure_networking() {
  # enable IPV4 port forwarding
  sysctl -w net.ipv4.ip_forward=1
  # update local firewall rules to allow container-container connections
  firewall-cmd --permanent --zone=public --add-rich-rule='rule family=ipv4 source address=172.17.0.0/16 accept'
  firewall-cmd --reload
}

#################
leader_up() {
  # Bring up Conjur Leader node
  $DOCKER run -d				\
    --name $CONJUR_LEADER_CONTAINER_NAME	\
    --label role=conjur_leader			\
    -p "$CONJUR_LEADER_PORT:443"		\
    -p "$CONJUR_LEADER_PGSYNC_PORT:5432"	\
    -p "$CONJUR_LEADER_PGAUDIT_PORT:1999"	\
    --restart always				\
    --security-opt seccomp=unconfined		\
    $CONJUR_APPLIANCE_IMAGE 

  echo "Waiting until container fully started..."
  sleep 15	

  # Configure Conjur Leader node
  echo "Configuring Conjur leader..."
  $DOCKER exec $CONJUR_LEADER_CONTAINER_NAME	\
                evoke configure master			\
                -h $CONJUR_LEADER_HOSTNAME		\
                -p $CONJUR_ADMIN_PASSWORD		\
		--master-altnames "$LEADER_ALTNAMES"	\
		--follower-altnames "$FOLLOWER_ALTNAMES" \
		--accept-eula				\
                $CONJUR_ACCOUNT

  mkdir -p $CACHE_DIR
  echo "Caching Conjur master cert ..."
  rm -f $CONJUR_CERT_FILE
  $DOCKER exec $CONJUR_LEADER_CONTAINER_NAME cat /opt/conjur/etc/ssl/conjur.pem > $CONJUR_CERT_FILE

  echo "Caching Conjur Follower seed files..."
  rm -f $FOLLOWER_SEED_FILE
  $DOCKER exec $CONJUR_LEADER_CONTAINER_NAME evoke seed follower conjur-follower > $FOLLOWER_SEED_FILE
}

############################
cli_config() {
  pushd ./bin
    tar xvzf $(ls cybr*.gz)
  popd
}

############################
load_demo_policy() {
  # Load policy & init variables
  $CYBR conjur append-policy -b root -f ./policy/demo-policy.yml
  $CYBR conjur set-secret -i secrets/db-username -v "This-is-the-DB-username"
  $CYBR	conjur set-secret -i secrets/db-password -v $(openssl rand -hex 12)
}

main "$@"
