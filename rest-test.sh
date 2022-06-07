#!/bin/bash 
source ./conjur.config

# As admin user, rotate the test-host API key
export CONJUR_AUTHN_API_KEY=$CONJUR_ADMIN_PASSWORD
export CONJUR_AUTHN_LOGIN=admin
export NEW_HOST_API_KEY=$($CYBR conjur rotate-api-key -l host/test-host | tr -d '\r\n')

# Set login creds to those for test-host
export CONJUR_AUTHN_LOGIN=host/test-host
export CONJUR_AUTHN_API_KEY=$NEW_HOST_API_KEY

# Authenticates and gets or sets value of a specified variable.
# NOTE: 'set' does not correctly handle values containing whitespace.

if [ -z "${CONJUR_APPLIANCE_URL}" ]; then
  echo "You must set CONJUR_APPLIANCE_URL and CONJUR_ACCOUNT before running this script."
  exit -1
fi

################  MAIN   ################
# $1 - command (get or set)
# $2 - name of variable
# $3 - value to set
main() {
  case $1 in
    get)  local command=get
	local variable_name=$2
	;;
    set)  local command=set
	local variable_name=$2
	local variable_value="$3"
	;;
    *)  printf "\nUsage: %s [ get | set ] <variable-name> [ <variable-value> ]\n" $0
	exit -1
  esac

  URLIFIED=$(urlify $CONJUR_AUTHN_LOGIN)
  response=$(curl -sk --data $CONJUR_AUTHN_API_KEY	\
	$CONJUR_APPLIANCE_URL/authn/$CONJUR_ACCOUNT/$URLIFIED/authenticate)
  AUTHN_TOKEN=$(echo $response | base64 | tr -d '\r\n')
  if [[ "$AUTHN_TOKEN" == "" ]]; then
    echo "Authentication failed..."
    exit -1
  fi

  variable_name=$(urlify "$variable_name")
  case $command in
    get)
	curl -sk -H "Content-Type: application/json" \
	-H "Authorization: Token token=\"$AUTHN_TOKEN\"" \
	$CONJUR_APPLIANCE_URL/secrets/$CONJUR_ACCOUNT/variable/$variable_name
	;;
    set)
	curl -sk -H "Content-Type: application/json" \
	-H "Authorization: Token token=\"$AUTHN_TOKEN\"" \
	--data "$variable_value" \
	$CONJUR_APPLIANCE_URL/secrets/$CONJUR_ACCOUNT/variable/$variable_name
	;;
  esac
}

################
# URLIFY - url encodes input string
# in: $1 - string to encode
# out: encoded string on stdout
urlify() {
        local str=$1; shift
        str=$(echo $str | sed 's= =%20=g')
        str=$(echo $str | sed 's=/=%2F=g')
        str=$(echo $str | sed 's=:=%3A=g')
        str=$(echo $str | sed 's=+=%2B=g')
        str=$(echo $str | sed 's=&=%26=g')
        str=$(echo $str | sed 's=@=%40=g')
        echo $str
}

main "$@"

