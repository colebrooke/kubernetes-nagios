#!/bin/bash

#########################################################
#       ./check_kube_nodes.sh                           #
#                                                       #
#       Nagios check script for kubernetes cluster      #
#       nodes.  Uses kubectl or API to check status     #
#       on each k8 node.                                #
#                                                       #
#       Author:  Justin Miller                          #
#                                                       #
#########################################################

type jq      >/dev/null 2>&1 || { echo >&2 "CRITICAL: The jq utility is required for this script to run."; exit 2; }
type kubectl >/dev/null 2>&1 || { echo >&2 "CRITICAL: The kubectl utility is required for this script to run."; exit 2; }


function usage {
cat <<EOF
Usage ./check_kube_nodes.sh [-t <TARGETSERVER> -c <CREDENTIALSFILE>] [-k <KUBE_CONFIG>]

Options:
  -t <TARGETSERVER>     # Optional, the endpoint for your Kubernetes API (otherwise will use kubectl)
  -c <CREDENTIALSFILE>  # Required if a <TARGETSERVER> API is specified, in the format outlined below
  -k <KUBE_CONFIG>      # Path to kube config file if using kubectl

Credentials file format:
machine yourEndPointOrTarget login yourUserNameHere password YOURPASSWORDHERE

EOF
exit 2
}

while getopts ":t:c:k:x:h" OPTIONS; do
        case "${OPTIONS}" in
                t) TARGET=${OPTARG} ;;
                c) CREDENTIALS_FILE="--netrc-file ${OPTARG}" ;;
                k) KUBE_CONFIG="--kubeconfig ${OPTARG}" ;;
                x) KUBE_CONTEXT="--context ${OPTARG}" ;;
                h) usage ;;
                *) usage ;;
        esac
done

# Comment out if you have SSL enabled on your K8 API
SSL="--insecure"
EXITCODE=0

if [ -z $TARGET ]; then
    # kubectl mode
    K8STATUS="$(kubectl $KUBE_CONFIG $KUBE_CONTEXT get nodes -o json)"
    if [ $(echo "$K8STATUS" | wc -l) -le 30 ]; then echo "CRITICAL - unable to connect to Kubernetes via kubectl!"; exit 3; fi
else
    # k8 API mode
    # Make call to Kubernetes API to get the status:
    K8STATUS="$(curl -sS $SSL $CREDENTIALS_FILE $TARGET/api/v1/nodes)"
    if [ $(echo "$K8STATUS" | wc -l) -le 30 ]; then echo "CRITICAL - unable to connect to Kubernetes API!"; exit 3; fi
fi

# Derive nodes from the json returned by the API
NODES=$(echo "$K8STATUS" | jq -r '.items[].metadata.name')

function returnResult () {
    CHECKSTATUS="$1"
    if [[ "$CHECKSTATUS" == "Critical" ]] && [ $EXITCODE -le 2 ]; then
        RESULT=$(echo -e "$CHECKSTATUS: $NODE has condition $CHECK - $STATUS\n$RESULT")
        EXITCODE=2
    elif [[ "$CHECKSTATUS" == "Warning" ]]; then
        RESULT=$(echo -e "$CHECKSTATUS: $NODE has condition $CHECK - $STATUS\n$RESULT")
        EXITCODE=1
    fi
    }

# Itterate through each node
for NODE in ${NODES[*]}; do
    CHECKS=$(echo "$K8STATUS" | jq -r '.items[] | select(.metadata.name=="'$NODE'") | .status.conditions[].type')
    # Itterate through each condition for each node
    for CHECK in ${CHECKS[*]}; do
        STATUS=$(echo "$K8STATUS" | jq '.items[] | select(.metadata.name=="'$NODE'") | .status.conditions[]'  | jq -r 'select(.type=="'$CHECK'") .status')
        case "$CHECK-$STATUS" in
            "OutOfDisk-True") returnResult Warning;;
            "MemoryPressure-True") returnResult Critical;;
            "DiskPressure-True") returnResult Critical;;
            "Ready-False") returnResult Warning;;
            "Ready-Unknown") returnResult Warning;;
            # Note the API only checks these 4 conditions at present. Others can be added here.
            *) returnResult OK;;
        esac
    done
done

case $EXITCODE in
    0) printf "OK - Kubernetes nodes all OK\n" ;;
    1) printf "" ;;
    2) printf "" ;;
esac

echo "$RESULT"
exit $EXITCODE
