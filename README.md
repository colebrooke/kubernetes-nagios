## kubernetes-nagios

Some checks for Kubernetes clusters, which can be use with Nagios, Zabbix, Icinga, or any other
monitoring system that can be configured to use an external shell script.
It's been tested on OSX, Ubuntu and Debian with bash. There are relativley few dependancies, but
the "jq" utility for processing json is required. If your Kubernetes API is not exposed, the checks
can use kubectl, in which case this will need to be installed and configured.

### check_kube_pods.sh

#### Usage
```
./check_kube_pods.sh [-t <TARGETSERVER> -c <CREDENTIALSFILE>] [-k <KUBE_CONFIG>] [-n <NAMESPACE>] [-w <WARN_THRESHOLD>] [-C <CRIT_THRESHOLD]
```

#### Options
```
  -t <TARGETSERVER>	# Optional, the endpoint for your Kubernetes API (otherwise will use kubectl)
  -c <CREDENTIALSFILE>	# Required if a <TARGETSERVER> API is specified, in the format outlined below
  -n <NAMESPACE>	# Namespace to check, for example, "kube-system". By default all are checked.
  -w <WARN_THRESHOLD>	# Warning threshold for number of container restarts [default: 5]
  -C <CRIT_THRESHOLD>	# Critical threshold for number of container restarts [default: 50]
  -k <KUBE_CONFIG>	# Path to kube config file if using kubectl
  -h			# Show usage / help
  -v			# Show verbose output
```

#### Example Output
```
$ ./check_kube_pods.sh -n kube-system                                                                                                                  master ◼
OK - Kubernetes pods are all OK
OK: Pod: nginx-ingress-controller-v1-zg7gw   Container: nginx-ingress-lb    Ready: true   Restarts: 1
OK: Pod: nginx-ingress-controller-v1-txc1w   Container: nginx-ingress-lb    Ready: true   Restarts: 1
OK: Pod: nginx-ingress-controller-v1-dffl3   Container: nginx-ingress-lb    Ready: true   Restarts: 1
```
```
$ ./check_kube_pods.sh -n kube-system -w 0 -c 30                                                                                                                   master ◼
WARNING - One or more pods show warning status!
Warning: Pod: nginx-ingress-controller-v1-zg7gw   Container: nginx-ingress-lb    Ready: true   Restarts: 1
Warning: Pod: nginx-ingress-controller-v1-txc1w   Container: nginx-ingress-lb    Ready: true   Restarts: 1
Warning: Pod: nginx-ingress-controller-v1-dffl3   Container: nginx-ingress-lb    Ready: true   Restarts: 1
```

### check_kube_deployments.sh

#### Usage
```
./check_kube_deployments.sh [-t <TARGETSERVER> -c <CREDENTIALSFILE>] [-k <KUBE_CONFIG>]
```

#### Example Output
```
$ ./check_kube_deployments.sh -t https://api.mykube-cluster.co.uk -c ~/my-credentails
OK - Kubernetes deployments are all OK
OK: kubernetes-dashboard-v1.4.0 has condition Available: True - Deployment has minimum availability.
OK: kubernetes-dashboard has condition Available: True - Deployment has minimum availability.
OK: kube-dns-autoscaler has condition Available: True - Deployment has minimum availability.
OK: kube-dns has condition Available: True - Deployment has minimum availability.
OK: heapster has condition Available: True - Deployment has minimum availability.
OK: dns-controller has condition Available: True - Deployment has minimum availability.
```

### check_kube_nodes.sh

This uses the Kubernetes API to check condition statuses across your nodes.

#### Usage
```
./check_kube_nodes.sh [-t <TARGETSERVER> -c <CREDENTIALSFILE>] [-k <KUBE_CONFIG>]
```
#### Example output
```
$ ./kubernetes-nagios ❯❯❯ ./check_kube_nodes.sh -t https://api.mykube-cluster.co.uk -c ~/my-credentails
WARNING - One or more nodes show warning status!
Warning: ip-10-123-81-96.eu-west-1.compute.internal has condition OutOfDisk - True
Warning: ip-10-123-82-87.eu-west-1.compute.internal has condition OutOfDisk - True
```

### check_kubernetes_api.sh

This check returns the health status of the overall cluster.

#### Usage
```
./check_kubernetes_api.sh [-t <TARGETSERVER> -c <CREDENTIALSFILE>] [-k <KUBE_CONFIG>]
```

### Dependancies

These scripts call the Kubernetes API, so this must be exposed to the machine running the script.
If not, the script will try and use the kubectl utility, which must be installed and configured.

The jq utility for parsing json is required.

### Credentials file format (when connecting to API)

The credentials must be supplied for the Kubernetes cluster API. It's in a file in the following format, 
this is required for all these checks in this project to work correctly.
```
$ cat my-credentails-file
machine yourEndPointOrTarget login yourUserNameHere password YOURPASSWORDHERE
```


