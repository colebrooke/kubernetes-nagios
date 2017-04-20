## kubernetes-nagios

Some checks for Kubernetes clusters, which can be use with Nagios, Zabbix, Icinga, or any other
monitoring system that can be configured to use an external shell script.
It's been tested on OSX, Ubuntu and Debian with bash. There are relativley few dependancies, but
the "jq" utility for processing json is required. If your Kubernetes API is not exposed, the checks
can use kubectl, in which case this will need to be installed and configured.

### Credentials file format (when connecting to API)

The credentials must be supplied for the Kubernetes cluster API. It's in a file in the following format, 
this is required for all these checks in this project to work correctly.
```
$ cat my-credentails-file
machine yourEndPointOrTarget login yourUserNameHere password YOURPASSWORDHERE
```

### check_kube_deployments.sh

#### Usage
```
./check_kube_deployments.sh [-t <TARGETSERVER> -c <CREDENTIALSFILE>]
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
./check_kube_nodes.sh [-t <TARGETSERVER> -c <CREDENTIALSFILE>]
```
#### Example output
```
$ ./kubernetes-nagios ❯❯❯ ./check_kube_nodes.sh -t https://api.mykube-cluster.co.uk -c ~/my-credentails
WARNING - One or more nodes show warning status!
Warning: ip-10-123-81-96.eu-west-1.compute.internal has condition OutOfDisk - True
Warning: ip-10-123-82-87.eu-west-1.compute.internal has condition OutOfDisk - True
```

### check_kubernetes.sh

This check returns the health status of the overall cluster.

#### Usage
```
./check_kubernetes.sh -t <TARGETSERVER> -c <CREDENTIALSFILE>
```

### Dependancies

These scripts call the Kubernetes API, so this must be exposed to the machine running the script.
If not, the script will try and use the kubectl utility, which must be installed and configured.

The jq utility for parsing json is required.

