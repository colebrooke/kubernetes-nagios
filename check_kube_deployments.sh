#!/bin/bash

#########################################################
#       ./check_kube_deployments.sh                     #
#                                                       #
#       Nagios check script for kubernetes cluster      #
#       deployments.  Uses API to check status for      #
#       each deployment.                                #
#       Author:  Justin Miller                          #
#                                                       #
#########################################################

type jq >/dev/null 2>&1 || { echo >&2 "CRITICAL: The jq utility is required for this script to run."; exit 2; }

function usage {
cat <<EOF
Usage ./check_kube_deployments.sh -t <TARGETSERVER> -c <CREDENTIALSFILE>

Options:
  -t <TARGETSERVER>     # Required, the endpoint for your Kubernetes API
  -c <CREDENTIALSFILE>  # Required, credentials for your Kubernetes API, in the format outlined below
  -n <NAMESPACE>        # Namespace to check, for example, "kube-system". By default all are checked.

Credentials file format:
machine yourEndPointOrTarget login yourUserNameHere password YOURPASSWORDHERE

EOF
exit 2
}

while getopts ":t:c:hn:k:x:" OPTIONS; do
        case "${OPTIONS}" in
                t) TARGET=${OPTARG} ;;
                c) CREDENTIALS_FILE=${OPTARG} ;;
                n) NAMESPACE_TARGET=${OPTARG} ;;
                k) KUBE_CONFIG="--kubeconfig ${OPTARG}" ;;
                x) KUBE_CONTEXT="--context ${OPTARG}" ;;
                h) usage ;;
                *) usage ;;
        esac
done

if [ ! -z $TARGET ] && [ -z $CREDENTIALS_FILE ]; then
        echo "Required argument -c <CREDENTIALSFILE> missing when specifing -t <TARGET>";
        exit 3;
fi

# Comment out if you have SSL enabled on your K8 API
SSL="--insecure"
EXITCODE=0

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
                NAMESPACES="$(curl -sS $SSL --netrc-file $CREDENTIALS_FILE $TARGET/api/v1/namespaces)"
                NAMESPACES=$(echo "$NAMESPACES" | jq -r '.items[].metadata.name')
        else
                NAMESPACES="$NAMESPACE_TARGET"
        fi
fi

function returnResult () {
    CHECKSTATUS="$1"
    RESULT=$(echo -e "$CHECKSTATUS: $DEPLOYMENT has condition $TYPE: $STATUS - $REASON\n$RESULT")
    if [[ "$CHECKSTATUS" == "Critical" ]] && [ $EXITCODE -le 2 ]; then EXITCODE=2; fi
    if [[ "$CHECKSTATUS" == "Warning" ]] && [ $EXITCODE -eq 0 ]; then EXITCODE=1; fi
    if [[ "$CHECKSTATUS" == "Unknown" ]] && [ $EXITCODE -eq 0 ]; then EXITCODE=3; fi
    }

# Itterate through each namespace
for NAMESPACE in ${NAMESPACES[*]}; do
    # get deployments data for the namespace
    if [[ -z $TARGET ]]; then
        # kubectl mode
        if [[ "$ALL_NAMESPACE_OPTION" == "true" ]]; then
            DEPLOYMENTS_STATUS=$(kubectl $KUBE_CONFIG $KUBE_CONTEXT get deployments --all-namespaces -o json)
        else
            DEPLOYMENTS_STATUS=$(kubectl $KUBE_CONFIG $KUBE_CONTEXT get deployments --namespace $NAMESPACE -o json)
        fi
    else
        # api mode
        DEPLOYMENTS_STATUS=$(curl -sS $SSL --netrc-file $CREDENTIALS_FILE $TARGET/apis/extensions/v1beta1/namespaces/$NAMESPACE/deployments/)
    fi

    DEPLOYMENTS=$(echo "$DEPLOYMENTS_STATUS" | jq -r '.items[].metadata.name')
    # Itterate through each deployment
    for DEPLOYMENT in ${DEPLOYMENTS[*]}; do
        TYPE=$(echo "$DEPLOYMENTS_STATUS" | jq -r '.items[] | select(.metadata.name=="'$DEPLOYMENT'") | .status.conditions |= sort_by(.lastTransitionTime) | .status.conditions[-1].type' )
        STATUS=$(echo "$DEPLOYMENTS_STATUS" | jq -r '.items[] | select(.metadata.name=="'$DEPLOYMENT'") | .status.conditions |= sort_by(.lastTransitionTime) | .status.conditions[-1].status' )
        REASON=$(echo "$DEPLOYMENTS_STATUS" | jq -r '.items[] | select(.metadata.name=="'$DEPLOYMENT'") | .status.conditions |= sort_by(.lastTransitionTime) | .status.conditions[-1].message' )
        # uncomment the following line to test a failure:
        # if [[ "$DEPLOYMENT" == "kubernetes-dashboard" ]]; then TYPE="Available"; STATUS="False"; fi
        case "${TYPE}-${STATUS}" in
            "Available-True") returnResult OK;;
            "Available-False") returnResult Warning;;
            *) returnResult Unknown ;;
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
