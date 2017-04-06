#!/bin/bash

#########################################################
#       ./check_kube_pods.sh				#
#                                                       #
#       Nagios check script for kubernetes cluster      #
#	pods.  Uses API to check status for each pod.	#
#       Author:  Justin Miller                          #
#                                                       #
#########################################################

type jq >/dev/null 2>&1 || { echo >&2 "CRITICAL: The jq utility is required for this script to run."; exit 2; }

function usage {
cat <<EOF
Usage: 
  ./check_kube_pods.sh -t <TARGETSERVER> -c <CREDENTIALSFILE> [-n <NAMESPACE>] [-w <WARN_THRESHOLD>] [-C <CRIT_THRESHOLD]

Options:
  -t <TARGETSERVER>	# Required, the endpoint for your Kubernetes API
  -c <CREDENTIALSFILE>	# Required, credentials for your Kubernetes API, in the format outlined below
  -n <NAMESPACE>	# Namespace to check, for example, "kube-system". By default all are checked.
  -w <WARN_THRESHOLD>	# Warning threshold for number of container restarts [default: 1]
  -C <CRIT_THRESHOLD>	# Critical threshold for number of container restarts [default: 5]

Credentials file format:
machine yourEndPointOrTarget login yourUserNameHere password YOURPASSWORDHERE

EOF
exit 2
}

SSL="--insecure"
EXITCODE=0
# Default thresholds for container restarts
WARN_THRESHOLD=1
CRIT_THRESHOLD=5

while getopts ":t:c:h:w:C:n:" OPTIONS; do
        case "${OPTIONS}" in
                t) TARGET=${OPTARG} ;;
                c) CREDENTIALS_FILE=${OPTARG} ;;
		w) WARN_THRESHOLD=${OPTARG} ;;
		C) CRIT_THRESHOLD=${OPTARG} ;;
		n) NAMESPACE_TARGET=${OPTARG} ;;
                h) usage ;;
                *) usage ;;
        esac
done

if [ -z $TARGET ]; then echo "Required argument -t <TARGET> missing!"; exit 3; fi
if [ -z $CREDENTIALS_FILE ]; then echo "Required argument -c <CREDENTIALSFILE> missing!"; exit 3; fi

WARN_THRESHOLD=$(($WARN_THRESHOLD + 0))
CRIT_THRESHOLD=$(($CRIT_THRESHOLD + 0))
####NAMESPACE_TARGET=$(echo "$NAMESPACE_TARGET" | xargs) 

# Make call to Kubernetes API to get the list of namespaces:
if [[ -z $NAMESPACE_TARGET ]]; then 
	NAMESPACES="$(curl -sS $SSL --netrc-file $CREDENTIALS_FILE $TARGET/api/v1/namespaces)"
	NAMESPACES=$(echo "$NAMESPACES" | jq -r '.items[].metadata.name')
else
	NAMESPACES="$NAMESPACE_TARGET"
fi


function returnResult () {
        RESULT=$(echo -e "$1: $2\n$RESULT")
        if [[ "$1" == "Critical" ]] && [ $EXITCODE -le 2 ]; then EXITCODE=2; fi
        if [[ "$1" == "Warning" ]] && [ $EXITCODE -eq 0 ]; then EXITCODE=1; fi
        if [[ "$1" == "Unknown" ]] && [ $EXITCODE -eq 0 ]; then EXITCODE=3; fi
        }

# Itterate through each namespace
for NAMESPACE in ${NAMESPACES[*]}; do
	# get deployments data for the namespace
	PODS_STATUS=$(curl -sS $SSL --netrc-file $CREDENTIALS_FILE $TARGET/api/v1/namespaces/$NAMESPACE/pods)
	if [ $(echo "$PODS_STATUS" | wc -l) -le 10 ]; then echo "CRITICAL - unable to connect to Kubernetes API!"; exit 2; fi
######	echo "$PODS_STATUS" && exit
	PODS=$(echo "$PODS_STATUS" | jq -r '.items[].metadata.name')
	# Itterate through each deployment
	for POD in ${PODS[*]}; do
		###
		POD_STATUS=$(echo "$PODS_STATUS" | jq -r '.items[] | select(.metadata.name=="'$POD'")')
		###
		POD_CONDITION_TYPES=$(echo "$POD_STATUS" | jq -r '.status.conditions[] | .type')
		# Itterate through each condition type
		for TYPE in ${POD_CONDITION_TYPES[*]}; do
			TYPE_STATUS=$(echo "$POD_STATUS" | jq -r '.status.conditions[] | select(.type=="'$TYPE'") | .status')
			if [[ "${TYPE_STATUS}" != "True" ]]; then
				returnResult Warning "Pod: $POD  $TYPE: $TYPE_STATUS"
			fi
		done
		CONTAINERS=$(echo "$POD_STATUS" | jq -r '.status.containerStatuses[].name')
		# Itterate through each container
		for CONTAINER in ${CONTAINERS[*]}; do

			CONTAINER_READY=$(echo "$POD_STATUS" | jq -r '.status.containerStatuses[] | select(.name=="'$CONTAINER'") | .ready')
			CONTAINER_RESTARTS=$(echo "$POD_STATUS" | jq -r '.status.containerStatuses[] | select(.name=="'$CONTAINER'") | .restartCount')
			if (( $CONTAINER_RESTARTS > $WARN_THRESHOLD && $CONTAINER_RESTARTS < $CRIT_THRESHOLD )); then 
				returnResult Warning "Pod: $POD   Container: $CONTAINER    Ready: $CONTAINER_READY   Restarts: $CONTAINER_RESTARTS"
			elif (( $CONTAINER_RESTARTS > $CRIT_THRESHOLD )); then
				returnResult Critical "Pod: $POD   Container: $CONTAINER    Ready: $CONTAINER_READY   Restarts: $CONTAINER_RESTARTS"
			fi
		done	
	done
done


case $EXITCODE in
	0) printf "OK - Kubernetes pods are all OK\n" ;;
	1) printf "WARNING - One or more pods show warning status!\n" ;;
	2) printf "CRITICAL - One or more pods show critical status!\n" ;;
esac

echo "$RESULT"
exit $EXITCODE
