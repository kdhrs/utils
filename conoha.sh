#!/bin/bash

USERNAME=""
PASSWORD=""

TENANT_ID=""
TENANT_NAME=""

IMAGE_CENTOS7=""
FLAVOR_512M=""
ADMIN_PASSWORD=""
KEY_NAME=""

SSH_HOST=""

LATEST_CREATE_SERVER_ID_FILE="/tmp/.latest_create_server_id"

HEADER="Accept:\ application/json"
REQUEST=$(cat << EOF
{
  "auth": {
    "passwordCredentials": {
      "username": "${USERNAME}",
      "password": "${PASSWORD}"
    },
    "tenantId": "${TENANT_ID}"
  }
}
EOF
)

TOKEN=$(curl -s -S -X POST -H "${HEADER}" -d "${REQUEST}" https://identity.tyo1.conoha.io/v2.0/tokens)
TOKEN_ID=$(echo $TOKEN |jq -r .access.token.id)
HEADER_TOKEN="X-Auth-Token: ${TOKEN_ID}"

SERVER_JSON=$(cat << EOF
{
  "server": {
    "imageRef": "${IMAGE_CENTOS7}",
    "flavorRef": "${FLAVOR_512M}",
    "adminPass":"${ADMIN_PASSWORD}",
    "key_name": "${KEY_NAME}",
    "security_groups": [
      {
        "name": "default"
      },
      {
        "name": "gncs-ipv4-all"
      }
    ]
  }
}
EOF
)

COMPUTE_BASE="https://compute.tyo1.conoha.io/v2/${TENANT_ID}"

get_response() {
  URL=$1
  local _RESULT=$(curl -s -S -X GET -H "${HEADER}" -H "${HEADER_TOKEN}" $URL)

  echo $_RESULT
}

delete_vm() {
  if [ ! -f "$LATEST_CREATE_SERVER_ID_FILE" ]; then
    echo "server not created."
    exit 1
  fi
  local _server_id=$(cat $LATEST_CREATE_SERVER_ID_FILE)
  local _response=$(curl -i -s -S -X DELETE -H "${HEADER}" -H "${HEADER_TOKEN}" "${COMPUTE_BASE}/servers/${_server_id}")
  rm -f $LATEST_CREATE_SERVER_ID_FILE

  echo $_response
}

create_vm() {
  local _response=$(curl -s -S -X POST -H "${HEADER}" -H "${HEADER_TOKEN}" -d "${SERVER_JSON}" "${COMPUTE_BASE}/servers")

  local _created_server_id=$(echo $_response |jq -r .server.id)
  rm -f $LATEST_CREATE_SERVER_ID_FILE
  echo $_created_server_id > $LATEST_CREATE_SERVER_ID_FILE
  local _response=$(get_response "${COMPUTE_BASE}/servers/${_created_server_id}")

  echo $_response
}

get_ipv4_addr() {
  local _json=${1}
  local _ipv4_addr=$(echo $_json |jq -r '.server.metadata.instance_name_tag' |sed 's/-/./g')

  echo $_ipv4_addr
}

set_ssh_config() {
  local _ipv4_addr=${1}
  perl -0pe "s/Host ${SSH_HOST}\n  Hostname.*/Host ${SSH_HOST}\n  Hostname ${_ipv4_addr}/m" ~/.ssh/config > ~/.ssh/config.new
  mv ~/.ssh/config.new ~/.ssh/config
}

case "$1" in
 create)
   SERVER_CREATED_RESPONSE=$(create_vm)
   echo $SERVER_CREATED_RESPONSE |jq .
   IPV4_ADDR=$(get_ipv4_addr $SERVER_CREATED_RESPONSE)
   set_ssh_config $IPV4_ADDR
   ;;
 delete)
   delete_vm
   ;;
 *)
   echo "Usage: conoha.sh {create|delete}"
   exit 1
esac

exit 0
