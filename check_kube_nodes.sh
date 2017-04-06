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

type jq >/dev/null 2>&1 || { echo >&2 "CRITICAL: The jq utility is required for this script to run."; exit 2; }

function usage {
cat <<EOF

Credentials file format:
machine yourEndPointOrTarget login yourUserNameHere password YOURPASSWORDHERE

Usage ./check_kube_nodes.sh -t <TARGETSERVER> -c <CREDENTIALSFILE>

EOF

exit 2
}

while getopts ":t:c:h" OPTIONS; do
        case "${OPTIONS}" in
                t) TARGET=${OPTARG} ;;
                c) CREDENTIALS_FILE=${OPTARG} ;;
                h) usage ;;
                *) usage ;;
        esac
done

if [ -z $TARGET ]; then echo "Required argument -t <TARGET> missing!"; exit 3; fi
if [ -z $CREDENTIALS_FILE ]; then echo "Required argument -c <CREDENTIALSFILE> missing!"; exit 3; fi


SSL="--insecure"
EXITCODE=0

# Make call to Kubernetes API to get the status:
K8STATUS="$(curl -sS $SSL --netrc-file $CREDENTIALS_FILE $TARGET/api/v1/nodes)"
if [ $(echo "$K8STATUS" | wc -l) -le 30 ]; then echo "CRITICAL - unable to connect to Kubernetes API!"; exit 2; fi

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
			"OutOfDisk-True") returnResult Warning;;
			"MemoryPressure-True") returnResult Critical;;
			"DiskPressure-True") returnResult Critical;;
			"Ready-False") returnResult Warning;;
			# Note the API only checks these 4 conditions at present. Others can be added here.
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
