#!/bin/bash

#########################################################
#       ./check_kubernetes.sh                           #
#                                                       #
#       Nagios check script for kubernetes cluster      #
#       This is a super simple check, with plenty       #
#       of room for improvements :)                     #
#       Author:  Justin Miller                          #
#       Website: https://github.com/colebrooke          #
#                                                       #
#########################################################

function usage {
cat <<EOF
Usage ./check_kubernetes [-t <TARGETSERVER> -c <CREDENTIALSFILE>] [-k <KUBE_CONFIG>]

Options:
  -t <TARGETSERVER>    # Required, the endpoint for your Kubernetes API
  -c <CREDENTIALSFILE> # Required, credentials for your Kubernetes API, in the format outlined below

Credentials file format:
machine yourEndPointOrTarget login yourUserNameHere password YOURPASSWORDHERE

EOF

exit 2
}

# Comment out if you have SSL enabled on your K8 API
SSL="--insecure"

while getopts ":t:c:hk:x:" OPTIONS; do
    case "${OPTIONS}" in
        t) TARGET=${OPTARG} ;;
        c) CREDENTIALS_FILE="--netrc-file ${OPTARG}" ;;
        h) usage ;;
        k) KUBE_CONFIG="--kubeconfig ${OPTARG}" ;;
        x) KUBE_CONTEXT="--context ${OPTARG}" ;;
        *) usage ;;
    esac
done

if [ -z $TARGET ]; then
    type kubectl >/dev/null 2>&1 || { echo >&2 "CRITICAL: The kubectl utility is required for this script to run if no API endpoint target is specified"; exit 3; }
    kubectl $KUBE_CONFIG $KUBE_CONTEXT proxy >/dev/null 2>&1 &
    PROXY_PID=$!
    sleep 1
    TARGET="http://127.0.0.1:8001"
fi

HEALTH=$(curl -sS $SSL $CREDENTIALS_FILE $TARGET/healthz)
BSC_HEALTH=$(curl -sS $SSL $CREDENTIALS_FILE $TARGET/healthz/poststarthook/bootstrap-controller)
EXT_HEALTH=$(curl -sS $SSL $CREDENTIALS_FILE $TARGET/healthz/poststarthook/extensions/third-party-resources)
BSR_HEALTH=$(curl -sS $SSL $CREDENTIALS_FILE $TARGET/healthz/poststarthook/rbac/bootstrap-roles)

if [ -n "$PROXY_PID" ]
then
    kill -15 $PROXY_PID
fi

case "$HEALTH $BSC_HEALTH $BSR_HEALTH" in
    "ok ok ok") echo "OK - Kubernetes API status is OK" && exit 0;;
    *)
        echo "WARNING - Kubernetes API status is not OK!"
        echo "/healthz - $HEALTH"
        echo "/healthz/poststarthook/bootstrap-controller - $BSC_HEALTH"
        echo "/healthz/poststarthook/extensions/third-party-resources - $EXT_HEALTH"
        echo "/healthz/poststarthook/rbac/bootstrap-roles - $BSR_HEALTH"
        exit 1
    ;;
esac


