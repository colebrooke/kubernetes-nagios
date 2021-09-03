#!/bin/bash

#########################################################
#       ./check_kube_pods.sh                            #
#                                                       #
#       Nagios check script for kubernetes cluster      #
#       pods.  Uses kubectl or API to check status      #
#       for each pod.                                   #
#                                                       #
#       Author:  Justin Miller                          #
#                                                       #
#########################################################

type jq >/dev/null 2>&1 || { echo >&2 "CRITICAL: The jq utility is required for this script to run."; exit 2; }

function usage {
cat <<EOF
Usage:
  ./check_kube_pods.sh [-t <TARGETSERVER> -c <CREDENTIALSFILE>] [-k <KUBE_CONFIG>] [-n <NAMESPACE>] [-w <WARN_THRESHOLD>] [-C <CRIT_THRESHOLD]

Options:
  -t <TARGETSERVER>     # Optional, the endpoint for your Kubernetes API (otherwise will use kubectl)
  -c <CREDENTIALSFILE>  # Required if a <TARGETSERVER> API is specified, in the format outlined below
  -n <NAMESPACE>        # Namespace to check, for example, "kube-system". By default all are checked.
  -w <WARN_THRESHOLD>   # Warning threshold for number of container restarts [default: 200]
  -C <CRIT_THRESHOLD>   # Critical threshold for number of container restarts [default: 1000]
  -k <KUBE_CONFIG>      # Path to kube config file if using kubectl
  -p <POD>              # Search for particular pods only
  -e <NUMBER_PODS>      # Expected number of pods in a ready condition
  -h                    # Show usage / help
  -v                    # Show verbose output

Credentials file format:
machine yourEndPointOrTarget login yourUserNameHere password YOURPASSWORDHERE

EOF
exit 2
}

# Comment out if you have SSL enabled on your K8 API
SSL="--insecure"
EXITCODE=0
# Default thresholds for container restarts
WARN_THRESHOLD=1000
CRIT_THRESHOLD=3000
EXPECTED_PODS=0
PODS_READY=0

while getopts ":t:c:hw:C:n:k:x:p:e:v" OPTIONS; do
        case "${OPTIONS}" in
                t) TARGET=${OPTARG} ;;
                c) CREDENTIALS_FILE="--netrc-file ${OPTARG}" ;;
                w) WARN_THRESHOLD=${OPTARG} ;;
                C) CRIT_THRESHOLD=${OPTARG} ;;
                n) NAMESPACE_TARGET=${OPTARG} ;;
                v) VERBOSE="true" ;;
                k) KUBE_CONFIG="--kubeconfig ${OPTARG}" ;;
                x) KUBE_CONTEXT="--context ${OPTARG}" ;;
                p) POD_SEARCH="${OPTARG}" ;;
                e) EXPECTED_PODS=${OPTARG} ;;
                h) usage ;;
                *) usage ;;
        esac
done


WARN_THRESHOLD=$(($WARN_THRESHOLD + 0))
CRIT_THRESHOLD=$(($CRIT_THRESHOLD + 0))

if [[ -z $TARGET ]]; then
    # use kubectl when no API endpoint is specified
    type kubectl >/dev/null 2>&1 || { echo >&2 "CRITICAL: The kubectl utility is required for this script to run if no API endpoint is specified"; exit 3; }
    if [[ -z $NAMESPACE_TARGET ]]; then
        ALL_NAMESPACE_OPTION="true"
        # should return all namespaces even when we set namespaces to default
        NAMESPACES="default"
    else
        NAMESPACES="$NAMESPACE_TARGET"
    fi
else
    # API target has been specified
    # Make call to Kubernetes API to get the list of namespaces:
    if [[ -z $NAMESPACE_TARGET ]] && [[ ! -z $TARGET ]]; then
        NAMESPACES="$(curl -sS $SSL $CREDENTIALS_FILE $TARGET/api/v1/namespaces)"
        NAMESPACES=$(echo "$NAMESPACES" | jq -r '.items[].metadata.name')
    else
        NAMESPACES="$NAMESPACE_TARGET"
    fi
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
    if [[ -z $TARGET ]]; then
        # kubectl mode
        if [[ "$ALL_NAMESPACE_OPTION" == "true" ]]; then
            PODS_STATUS=$(kubectl $KUBE_CONFIG $KUBE_CONTEXT get pods --all-namespaces -o json)
        else
            PODS_STATUS=$(kubectl $KUBE_CONFIG $KUBE_CONTEXT get pods --namespace $NAMESPACE -o json)
        fi

    else
        # api mode
        PODS_STATUS=$(curl -sS $SSL $CREDENTIALS_FILE $TARGET/api/v1/namespaces/$NAMESPACE/pods)
    fi
    if [ $(echo "$PODS_STATUS" | wc -l) -le 10 ]; then echo "CRITICAL - unable to connect to kubernetes cluster!"; exit 3; fi

    if [ -z $POD_SEARCH ]; then
        PODS=$(echo "$PODS_STATUS" | jq -r '.items[].metadata.name')
    else
        PODS=$(echo "$PODS_STATUS" | jq -r '.items[].metadata.name'| grep "$POD_SEARCH")
    fi

    # Itterate through each pod
    for POD in ${PODS[*]}; do
        POD_STATUS=$(echo "$PODS_STATUS" | jq -r '.items[] | select(.metadata.name | contains("'$POD'"))')
        POD_CONDITION_TYPES=$(echo "$POD_STATUS" | jq -r '.status.conditions[] | .type')
        # Itterate through each condition type
        for TYPE in ${POD_CONDITION_TYPES[*]}; do
            TYPE_STATUS=$(echo "$POD_STATUS" | jq -r '.status.conditions[] | select(.type=="'$TYPE'") | .status')
            #echo "$TYPE_STATUS"
            #echo "-------------"
            if [[ "${TYPE_STATUS}" != "True" ]]; then
                returnResult OK "Pod: $POD  $TYPE: $TYPE_STATUS"
            else
                if [[ "${TYPE}" == "Ready" ]]; then PODS_READY=$((PODS_READY+1)); fi
                if [[ "$VERBOSE" == "true" ]]; then returnResult OK "Pod: $POD  $TYPE: $TYPE_STATUS"; fi
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
            elif (( $CONTAINER_RESTARTS > 0 )); then
                returnResult OK "Pod: $POD   Container: $CONTAINER    Ready: $CONTAINER_READY   Restarts: $CONTAINER_RESTARTS"
            fi
        done
    done
done

if (( $EXPECTED_PODS > $PODS_READY )); then returnResult Critical "$POD_SEARCH only has $PODS_READY pods ready, expecting $EXPECTED_PODS!"; fi

case $EXITCODE in
    0) printf "OK - $POD_SEARCH pods are all OK, found $PODS_READY in ready state.\n" ;;
    1) printf "Warning - $POD_SEARCH pods show warning status, $PODS_READY in ready state.\n" ;;
    2) printf "Critical - $POD_SEARCH pods show critical status, $PODS_READY in ready state.\n" ;;
esac

echo "$RESULT"
exit $EXITCODE
