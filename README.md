## kubernetes-nagios

Some nagios checks for Kubernetes clusters.

### check_kube_nodes.sh

This uses the Kubernetes API to check condition statuses across your nodes.

#### Usage
```
./check_kube_nodes.sh -t <TARGETSERVER> -c <CREDENTIALSFILE>
```
#### Example output
```
~/kubernetes-nagios ❯❯❯ ./check_kube_nodes.sh -t https://api.xyz.mydomain.co.uk -c ~/my-credentails
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

The jq utility for parsing json is required.

