#!/bin/bash

#########################################################
# 	./check_kubernetes.sh 				#
#							#
# 	Nagios check script for kubernetes cluster	#
#	This is a super simple check, with plenty	#
#	of room for improvements :)			#
# 	Author:  Justin Miller				#
# 	Website: https://github.com/colebrooke		#
# 							#
#########################################################

function usage {
cat <<EOF

Credentials file format:
machine yourEndPointOrTarget login yourUserNameHere password YOURPASSWORDHERE

Usage ./check_kubernetes -t <TARGETSERVER> -c <CREDENTIALSFILE>

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

HEALTH=$(curl -sS --insecure --netrc-file $CREDENTIALS_FILE https://$TARGET/healthz)
BSC_HEALTH=$(curl -sS --insecure --netrc-file $CREDENTIALS_FILE https://$TARGET/healthz/poststarthook/bootstrap-controller)
EXT_HEALTH=$(curl -sS --insecure --netrc-file $CREDENTIALS_FILE https://$TARGET/healthz/poststarthook/extensions/third-party-resources)
BSR_HEALTH=$(curl -sS --insecure --netrc-file $CREDENTIALS_FILE https://$TARGET/healthz/poststarthook/rbac/bootstrap-roles)


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


