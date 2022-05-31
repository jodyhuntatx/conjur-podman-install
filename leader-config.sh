#!/bin/bash

source ./conjur.config

# This script deletes running instances and brings up 
#   initialized Conjur Leader & CLI nodes.

#################
main() {
  teardown_conjur
  if [[ "$1" == "stop" ]]; then
    exit -1
  fi
  #configure_networking
  leader_up
  ./cli-config.sh
  load_demo_policy
  echo
  echo
  echo "Performing smoke test secret retrieval from Leader:"
  echo -n "DB username: "
  $DOCKER exec -it $CLI_CONTAINER_NAME		\
 	conjur variable value secrets/db-username 
  echo
  echo -n "DB password: "
  $DOCKER exec -it $CLI_CONTAINER_NAME		\
 	conjur variable value secrets/db-password
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
load_demo_policy() {
  # Load policy & init variables
  cat ./policy/demo-policy.yml			\
  | $DOCKER exec -i $CLI_CONTAINER_NAME	\
	conjur policy load root -
  $DOCKER exec -it $CLI_CONTAINER_NAME	\
  	conjur variable values add secrets/db-username "This-is-the-DB-username"
  $DOCKER exec -it $CLI_CONTAINER_NAME	\
  	conjur variable values add secrets/db-password $(openssl rand -hex 12)
}

main "$@"
