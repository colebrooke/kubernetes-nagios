#!/bin/bash

#########################################################
#       ./check_kube_nodes.sh                           #
#                                                       #
#       Nagios check script for kubernetes cluster      #
#	nodes.  Uses API to check status for each	#
#	node.						#
#       Author:  Justin Miller                          #
#                                                       #
#########################################################

## TODO: check dependancies
## TODO: verify API endpoint
## TODO: add these as script arguments
TARGET="https://your-kubernetes-endpoint.co.uk"
CREDS="~/kube8-creds"

SSL="--insecure"
EXITCODE=0

# Make call to Kubernetes API to get the status:
K8STATUS="$(curl -sS $SSL --netrc-file ~/kube8-creds $TARGET/api/v1/nodes)"

# Derive nodes from the json returned by the API
NODES=$(echo "$K8STATUS" | jq -r '.items[].metadata.name')

function returnResult () {
	CHECKSTATUS="$1"
	RESULT=$(echo -e "$CHECKSTATUS: $NODE has condition $CHECK - $STATUS\n$RESULT")
	if [[ "$CHECKSTATUS" == "Critical" ]] && [ $EXITCODE -le 2 ]; then 
		EXITCODE=2
	elif [[ "$CHECKSTATUS" == "Warning" ]]; then
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
			"OutOfDisk-False") returnResult Warning;;
			"MemoryPressure-True") returnResult Critical;;
			"DiskPressure-True") returnResult Critical;;
			"Ready-False") returnResult Warning;;
			*) : ;;
		esac
	done
done

case $EXITCODE in
	0) printf "OK - Kubernetes nodes all OK" ;;
	1) printf "WARNING - One or more nodes show warning status!\n" ;;
	2) printf "CRITICAL - One or more nodes show critical status!\n" ;;
esac

echo "$RESULT"
exit $EXITCODE
