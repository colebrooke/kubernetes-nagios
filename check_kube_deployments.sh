#!/bin/bash

#########################################################
#       ./check_kube_deployments.sh			#
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

Usage ./check_kube_deployments.sh -t <TARGETSERVER> -c <CREDENTIALSFILE>

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


SSL="--insecure"
EXITCODE=0

# Make call to Kubernetes API to get the list of namespaces:
NAMESPACES="$(curl -sS $SSL --netrc-file $CREDENTIALS_FILE $TARGET/api/v1/namespaces)"
if [ $(echo "$NAMESPACES" | wc -l) -le 10 ]; then echo "CRITICAL - unable to connect to Kubernetes API!"; exit 2; fi
NAMESPACES=$(echo "$NAMESPACES" | jq -r '.items[].metadata.name')

function returnResult () {
	CHECKSTATUS="$1"
	RESULT=$(echo -e "$CHECKSTATUS: $DEPLOYMENT has condition $TYPE: $STATUS - $REASON\n$RESULT")
	if [[ "$CHECKSTATUS" == "Critical" ]] && [ $EXITCODE -le 2 ]; then EXITCODE=2; fi
	if [[ "$CHECKSTATUS" == "Warning" ]] && [ $EXITCODE -eq 0 ]; then EXITCODE=1; fi
	}

# Itterate through each namespace
for NAMESPACE in ${NAMESPACES[*]}; do
	# get deployments data for the namespace
	DEPLOYMENTS_STATUS=$(curl -sS $SSL --netrc-file $CREDENTIALS_FILE $TARGET/apis/extensions/v1beta1/namespaces/$NAMESPACE/deployments/)
	DEPLOYMENTS=$(echo "$DEPLOYMENTS_STATUS" | jq -r '.items[].metadata.name')
	# Itterate through each deployment
	for DEPLOYMENT in ${DEPLOYMENTS[*]}; do
		TYPE=$(echo "$DEPLOYMENTS_STATUS" | jq -r '.items[] | select(.metadata.name=="'$DEPLOYMENT'") | .status.conditions[].type' )
		STATUS=$(echo "$DEPLOYMENTS_STATUS" | jq -r '.items[] | select(.metadata.name=="'$DEPLOYMENT'") | .status.conditions[].status' )
		REASON=$(echo "$DEPLOYMENTS_STATUS" | jq -r '.items[] | select(.metadata.name=="'$DEPLOYMENT'") | .status.conditions[].message' )
		case "$TYPE-$STATUS" in
			"Avilability-True") returnResult OK;;
			"Avilability-False") returnResult Warning;;
			*) returnResult OK ;;
		esac
	done
done

case $EXITCODE in
	0) printf "OK - Kubernetes deployments are all OK\n" ;;
	1) printf "WARNING - One or more deployments show warning status!\n" ;;
	2) printf "CRITICAL - One or more nodes show critical status!\n" ;;
esac

echo "$RESULT"
exit $EXITCODE
