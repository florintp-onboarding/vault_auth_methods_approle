#!/bin/bash
# Default port exposed from container is $VAULT_PORT or the ARGV
# Syntax is:
#           ./work_with_auth_methods.sh approle

# Default license is collected from the license file ../vault_license.hlic
# The demo will be kept alive for a number of seconds as per variable TIMEDEMO
# Default value for TIMEDEMO is 3600 seconds. TIMEDEMO=3600
export TIMEDEMO=3600

# DEBUG information is printed if there is a terminal and if the value is greater than ZERO.
export DEBUG=0
export VAULT_LICENSE=$(cat ../vault_license.hlic)
export VAULT_VERSION=$2 ; [ "X$VAULT_VERSION" == "X" ] && export VAULT_VERSION=":latest"|| export VAULT_VERSION=":$VAULT_VERSION"

function xecho {
    [ -t ] && (echo -ne "$@\n")
}

[ $DEBUG -gt 0 ] && xecho -ne "\nLicense used:$VAULT_LICENSE\n"

function create_container()
{
  local _errmsg=0
  local VAULT_PORT=$1
  local CLUSTER_VAULT_PORT=$(($VAULT_PORT + 1))
  xecho "\n### Creating vault container: vault$VAULT_PORT\n"
  local VAULT_ADDR=http://localhost:$VAULT_PORT
  local VAULT_TOKEN=$(echo "my_temporary_token_$VAULT_PORT" |base64 )
  xecho -ne "### Token used: $VAULT_TOKEN\n"
  [ $DEBUG -gt 0 ] && xecho "\n### Executing the docker command for  vault-$VAULT_PORT\ndocker run \ 
--cap-add=IPC_LOCK \ 
-e VAULT_API_ADDR=\"http://0.0.0.0:$VAULT_PORT\" \\
-e VAULT_LICENSE=\$(echo \$VAULT_LICENSE) \\
--name vault$(echo $VAULT_PORT) \\
-e 'VAULT_LOCAL_CONFIG={"raw_storage_endpoint":"true","storage":{"raft":{"path":"/tmp/","node_id":"vault_$VAULT_PORT"}},"ui":"true","listener":{"tcp":{"address":"0.0.0.0:$VAULT_PORT","tls_disable":"true"}},"api_addr":"http://vault-$PORT:$VAULT_PORT","cluster_addr":"http://vault-$PORT:$CLUSTER_VAULT_PORT"}'
--detach \\
hashicorp/vault-enterprise \n"
 xecho "\n Creating docker container user $VAULT_VERSION image\n"
  #  INIT_RESPONSE=$(docker run --detach --name vault-$(echo $VAULT_PORT) -p $VAULT_PORT:8200 -p $CLUSTER_VAULT_PORT:8201 --cap-add=IPC_LOCK -e VAULT_LICENSE=$(echo $VAULT_LICENSE)  -e 'VAULT_LOCAL_CONFIG={"raw_storage_endpoint":"true","storage":{"raft":{"path":"/tmp/","node_id":"vault_'$VAULT_PORT'"}},"listener":{"tcp":{"address":"0.0.0.0:8200","tls_disable":"true"}},"api_addr":"http://vault-'$PORT':8200","cluster_addr":"http://vault-'$PORT':8201"}' hashicorp/vault-enterprise:$VAULT_VERSION server )
  # Create a bridge network for containers visibility
  # https://docs.docker.com/network/network-tutorial-standalone/
  # Used as example: https://github.com/hashicorp/k8s-101

  INIT_RESPONSE=$(docker network rm alpine-net ; docker network create --driver bridge alpine-net ; docker run --detach --name vault-$(echo $VAULT_PORT) -p $VAULT_PORT:$VAULT_PORT -p $CLUSTER_VAULT_PORT:$CLUSTER_VAULT_PORT --cap-add=IPC_LOCK -e VAULT_LICENSE=$(echo $VAULT_LICENSE)  -e 'VAULT_LOCAL_CONFIG={"raw_storage_endpoint":"true","storage":{"raft":{"path":"/tmp/","node_id":"vault_'$VAULT_PORT'"}},"ui":"true","listener":{"tcp":{"address":"0.0.0.0:'$VAULT_PORT'","tls_disable":"true"}},"api_addr":"http://vault'$VAULT_PORT':'$VAULT_PORT'","cluster_addr":"http://vault'$VAULT_PORT':'$CLUSTER_VAULT_PORT'"}' --network alpine-net hashicorp/vault-enterprise$VAULT_VERSION server )
  _errmsg=$?
  [ $DEBUG -gt 0 ] && xecho "### Status: ${_errmsg} : docker_id=$INIT_RESPONSE" 
  return ${_errmsg}
}

function exercise1()
{
  xecho "\nFollowing https://developer.hashicorp.com/vault/tutorials/auth-methods/approle"
  vault secrets enable -path=secret -description="Secret KV engine" -version=2  kv
  tee jenkins.hcl << EOFT1
# Read-only permission on 'secret/data/myapp/*' path
path "secret/data/myapp/*" {
  capabilities = [ "read" ]
}
path "secret/data/mysql/webapp" {
  capabilities = [ "read" ]
}
EOFT1

  tee data1.json  << EOFT4
{
  "url": "foo.example.com:35533",
  "db_name": "users",
  "username": "admin",
  "password": "passw0rd"
}
EOFT4

  tee data2.json  << EOFT2
{
  "url": "not.used.yet:35533",
  "db_name": "users",
  "username": "admin",
  "password": "redacted"
}
EOFT2

tee approle_admin.json << EOFT3
# Mount the AppRole auth method
path "sys/auth/approle" {
  capabilities = [ "create", "read", "update", "delete", "sudo" ]
}

# Configure the AppRole auth method
path "sys/auth/approle/*" {
  capabilities = [ "create", "read", "update", "delete" ]
}

# Create and manage roles
path "auth/approle/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

# Write ACL policies
path "sys/policies/acl/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

# Write test data
# Set the path to "secret/data/mysql/*" if you are running kv-v2
path "secret/mysql/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

EOFT3
tee guest.json << EOFT5
# Mount the AppRole auth method
path "sys/auth/approle" {
  capabilities = [ "read", "list" ]
}
path "kv/data/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}
EOFT5
  vault policy write jenkins jenkins.hcl
  vault policy write  guest guest.json

  vault kv put secret/myapp/db-config @data1.json
  vault kv put secret/mysql/webapp  @data2.json

  xecho "\n### Enable secret approle?" && read x
  vault auth enable approle

  vault write auth/approle/role/jenkins token_policies="jenkins, guest" \
      token_ttl=1h token_max_ttl=4h
  vault read auth/approle/role/jenkins

  vault read -format=json auth/approle/role/jenkins/role-id \
      | jq -r ".data.role_id" > role_id.txt
  vault read auth/approle/role/jenkins/role-id

  vault write -f -format=json auth/approle/role/jenkins/secret-id \
      | jq -r ".data.secret_id" > secret_id.txt

  xecho "To login, you must pass the role ID (role_id.txt) and secret ID (secret_id.txt).
  Let's log in using the approle auth method and store the generated client token in a file named, app_token.txt:"

  vault write -format=json auth/approle/login \
      role_id=$(cat role_id.txt) secret_id=$(cat secret_id.txt) \
      | jq -r ".auth.client_token" > app_token.txt
  [ -s app_token.txt ] && export APP_TOKEN=$(cat app_token.txt) 
  [[ "X$APP_TOKEN" == "X" ]] && echo "No TOKEN was generated!" 

  vault token lookup $(cat app_token.txt)
  xecho "\nThe token has read-only permission on the secret/myapp/* and secret/data/mysql/ paths and cannot DELETE!"
  VAULT_TOKEN=$APP_TOKEN vault kv delete secret/mysql/webapp
  xecho "\nThe token has read-only permission on the secret/myapp/* and secret/data/mysql/ paths and can READ!"
  VAULT_TOKEN=$APP_TOKEN vault kv get secret/mysql/webapp
  return 0
}

function init_and_unseal()
{
   local found_leader=0
   local VAULT_PORT=$1
   export VAULT_ADDR=http://127.0.0.1:$VAULT_PORT
   vault status 2>/dev/null 1>&2  ; xecho "\nVault status: $?"
   while vault status 1>/dev/null 2>&1 ; exitcode=$?; [ ! $exitcode -eq 2 ]  ; do
       #xecho "\rStill starting up .....$(date)"
       sleep 1
   done
   # Check for previous leader init files
   for local_init in $(seq 8200 2 9000 ) ; do
        if [ -f init.keys_$local_init ] ; then
	  xecho "\nFound another docker init.keys_$local_init!\nAssuming that leader is unsealed...\n$(grep Key init.keys_$local_init)\n"
	  cp init.keys_$local_init init.keys_$VAULT_PORT
	  vault operator raft join "http://vault$local_init:$local_init"
          found_leader=1 && break 
        else
	  xecho "\nNo leader found."
	fi
   done
   if [ $found_leader -gt 0 ] ; then
      xecho "### Vault is already initialized and init_keys already present"
   else
      xecho "### Init Vault server"
      time vault operator init > init.keys_$VAULT_PORT
   fi
   export VAULT_TOKEN=$(cat init.keys_$VAULT_PORT|grep Root|awk '{print $NF}')
   xecho "### Unseal Vault server"
   for i in $(cat init.keys_$VAULT_PORT|grep "Unseal"|awk '{print $NF}' ) ; do
	   xecho "Working on unseal key: $i"
           vault operator unseal $i 1>/dev/null 2>&1
   done
   while ! vault operator raft list-peers 1>/dev/null 2>&1 ; do
	  xecho "\rWaiting for raft to stabilize .....$(date)"
   done
   xecho '\nDone - Raft is stable'
   vault login $VAULT_TOKEN 2>/dev/null
   docker exec -d -ti  vault-$VAULT_PORT mkdir /vault/audit
   docker exec -d -ti  vault-$VAULT_PORT chown vault.vault /vault/audit
   docker exec -d -ti  vault-$VAULT_PORT chmod 0700 /vault/audit
   docker exec -d -ti  vault-$VAULT_PORT ls -ltric /vault
   [ $found_leader -eq 0 ] && vault audit enable file file_path=/vault/audit/audit.log
   vault read sys/license/status
   vault secrets list
   vault audit list
   return 0
   }

# MAIN BLOCK
# Parse the arguments received from calling the script
export containers=""
export arguments=$#
export action=""
export VAULT_PORT=8200
while [[ "$#" -gt 0 ]]; do
    case $1 in
	   approle)
	   for local_port in $(seq 8200 2 9000) ; do
	      nc -zv 127.0.0.1 $local_port || break  
	   done
	   export VAULT_PORT=$local_port && unset local_port
	   action="create_container $VAULT_PORT "
	   export containers="$containers vault-$VAULT_PORT"
	   #create_container $local && containers="$containers vault$VAULT_PORTt"
	   ;;
          1.[0-9]*)
           action="$action $1"
	  # create_container $local_port $1  && containers="$containers vault$VAULT_PORT"
	   ;;
         *)
	   xecho "\nSkipping this argument."
	   ;; 
    esac
    shift
done

if [ "X$containers" == "X" ] ; then
   echo -ne "\n# Invalid argument passed for vault: <$1> \n is not in the list of:  approle.\n"
else
  echo $action
  eval $action
  init_and_unseal $VAULT_PORT
  xecho "\nPerform the exercise?<Y/n>[n]"
  read ans
  if [[ "X$(echo $ans|tr '[:upper:]' '[:lower:]')" == "Xy" ]]  ; then
     exercise1
  else
    :
  fi
  echo "Sleeping $TIMEDEMO seconds" ; sleep $TIMEDEMO
fi

for container in $(docker ps -q -a -f  "ancestor=hashicorp/vault-enterprise"  --format "{{.Names}}") ; do
   # If the container is in our list of started containers we will remove it otherwise it will print out the manual cleanup.
   if [ $(echo $containers|grep $container|wc -l) -ge 1 ]  ; then
      [ -t ] && echo -ne "\n### Removing container $container "
      docker rm $container --force 1>/dev/null 
      [ $? -eq 0 ] && [ -t ] && echo -ne "OK" || echo -ne "Failed." 
   else
       [ -t ] && echo -ne "\n### Manual retry\ndocker rm $container --force"
   fi
done

rm -f init.keys_$VAULT_PORT
xecho "\nCleanup all:\nfor i in \$(docker ps -qa|grep 'vault-'|awk '{print \$1}') ; do 
docker rm --force \$i 
done"


