# Code wise

Looks like I mixed a bit naming cases... decide on using CamelCase or not, and make it so through all the code

# others
check bash version - older ones do NOT have BASH_SOURCE* variables for example
check lxd, kubectl versions
check os version (to not be too old)
check 'sort -V' really works - early at program start

make it conformant - https://github.com/cncf/k8s-conformance

lxd - change url to ubuntu images in case http_proxy is set, to go over http:// and benefit from proxy. Would speed only setup phase though.

k8s base image - don't push it as image to be deleted later, try to create master and worker directly from the container
   try maybe this: copy base container into 'master', continue in this container as worker, and in the other , as master setup.
   this would avoid copying around bytes


# Addons
## cluster wide storage class
Maybe nfs, exposed via a storage class.
We do have right now also 'localhost-storage-class', but that will force the pod to stay on the same initial node.
We want something that would allow the pods to be rechsedueled on different nodes.


## Ingress controller

## ? Cert-manager

## ? Prometheus

## Docker registry

