## Simple PoC project following https://developer.hashicorp.com/vault/tutorials/auth-methods/approle

-----


### What is it :

  This project creates a docker instance of Vault in a Raft (integrated storage).


### Prerequisites :

  - Docker

### Usage :


# Default port exposed from container is $VAULT_PORT or the ARGV
# Syntax is:
#           ./work_with_auth_methods.sh approle

# Default license is collected from the license file ../vault_license.hlic
# The demo will be kept alive for a number of seconds as per variable TIMEDEMO
# Default value for TIMEDEMO is 3600 seconds. TIMEDEMO=3600

