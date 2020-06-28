* [About](#about)
* [Motivation](#motivation)
* [Features](#features)
* [Tech - how it works](#tech---how-it-works)
* [Platforms and versions](#platforms-and-versions)
* [Using it](#using-it)
 * [Install](#install)
 * [Command line parameters](#command-line-parameters)
 * [One time setup](#one-time-setup)
 * [Creating a cluster](#creating-a-cluster)
 * [Stopping the cluster](#stopping-the-cluster)
 * [Starting back the cluster](#starting-back-the-cluster)
 * [Removing the cluster](#removing-the-cluster)
* [Accessing your services](#accessing-your-services)
* [Addons](#addons)
* [Development](#development)

# About
This is a shell script that will allow you to create **multiple** Kubernetes clusters, maybe of **different** versions, with **multiple** nodes.
Each node will be a [LXD container](https://linuxcontainers.org/lxd/introduction/), meaning that it is going to be lightweight - compared to a full VirtualBox/KVM virtual machine node for example. Since it is based on LXD - for now it will run only on Linux. But even if you're not working on Linux you could start only one full virtual machine (VM), into which you would manage all your clusters and nodes.



# Motivation

NOTE: This script was started some time ago, things might have changed meanwhile, regarding similar tools. Please let me know.
For a longer version and some comparisons, check [motivation](docs/motivation.md)

In short: I needed a quick way to start multiple Kubernetes clusters, with multiple nodes, for development purposes, on my computer. As light weight as possible. And current solutions (especially when I started this) either can not do all these things or do not work well.

Why multiple nodes? Well.. you **do** want to test HA setups and Deployments with more than 1 pod, right?

# Notes
This is intended for **development** purposes and not production.

When referring to the times something took to run - reference is a desktop computer:

- CPU: Intel Xeon E3-1240 V2 @ 3.4Ghz (kindof' 2012 I7 processor without a GPU)
- RAM: 32Gb
- SSD Samsung EVO 850 250Gb (~ 80% used capacity)



# Features

**Shell script** - setup, install, stop, start, delete, and then... it is out of your way - no other services/processes running.

**Lightweight**: it uses LXD containers which are very light compared to a full blown virtual machine like VirtualBox/KVM. And once setup and containers running, nothing else is still running and consuming CPU (as opposed to Juju, let's say)

**Multiple environments**: imagine  you're working on:

- a helm chart and you want to test it
- a development version of your home kubernetes cluster
- a development version of one of your site's kubernetes cluster

You can do this, by using a 'prefix name'. And then you just tell ```kubectl``` which one to work with, via ```--context NAME```

**Multiple Kubernetes versions**: each cluster can have its own kubernetes version
For example, you can have one cluster running 1.13, one 1.16 and one the latest 1.18

**Multi node clusters**: you'd like to simulate a real cluster with more than one node. Maybe you need to test some kind of HA setup of mysql, redis, etc. Or a deployment with more than one replicas which is also having some affinity rules. Or you just want to be **somehow** closer to your actual production environments.

# Tech - how it works
All the system is made of a multi-file bash shell script. For more technical/developer details, see [DEV](docs/DEV.md)

- it does some checks on your system: lxd installed, storage type, some sysfs settings, kernel modules. It will need to run 'sudo' for some of the checks and to fix issues.

- it might do some LXD server setup changes (storage pool, DHCP range)

- it creates a specific lxd profile

- it creates 2 lxd images that will be used later for *master* and *worker* nodes. This is the step that takes most of the time, but it is done only one time, per Kubernetes version you want to have.
	Inside, setup will be using the good ```kubeadm``` program. Also, for later startup speed reasons, some docker images will be retrieved.
  Images are getting quite big for now, maybe things can be improved.
Images could also theoretically just be present on the net (of your company) and downloaded instead of being built.
	
- when asked for, it creates a master node, based on the images created before. Takes 1min on the reference desktop.
	
  During this step, your local *kubectl* configuration is also updated so that you can later easily access this cluster.

- when asked for, **add** a new node (I call it 'worker node') to the cluster, based, as well, on the previously created images. Takes 40s on the reference desktop. You can run this step as many times you need.

NOTE: you can specify the version of Kubernetes to install and use, via ```--k8s-version 1.16.2``` for example. Needed only when creating the images with ```--setup``` or the master container with ```--master```



# Platforms and versions
Platforms it runs on: obviously, first, where ```lxd``` works - that is, for now, on Linux systems. For other OSes, you could run all your clusters in a single full Linux virtual machine.

So far, tested on:
* virtual machines: ubuntu 18.04, 19.10, 20.04; with k8s 1.13.12, 1.16.2, 1.18.2
* Manjaro/Arch, k8s 1.13.12, 1.16.2, 1.18.2

See file [test/kitchen.yml](test/kitchen.yml) for the versions that are tested.

Because it is using LXD containers, if you have LXD and kubectl installed on your machine and working, chances are it will work for other Linux distro as well.

----
# Using it

## Install
For now, you just *git clone* this repository somewhere on your machine. And then you ensure you can easily access the main script ```k8s-on-lxd.sh``` (a symlink into ```~/bin/k8s-on-lxd.sh``` for example)

You should already have preinstalled things like: kubectl, lxd (doh!) plus a few other tools used during various phases: pwgen, netstat or ip, grep, sysctl, sort, jq, shuf.

The script will check for them before running. In case you do not know how to install them for your particular distro, you can try to run ```test/setup-pre-req.sh```


## Troubleshooting
Some common issues you could encounter are tracked into a separate [document](docs/troubleshooting.md)

## Command line parameters
Script's parameter order: it is important (for now). That is, give necessary parameters before the one telling the script what to do.

Examples:  

- --k8s-version before --setup or --master
- --name NAME before --master or --worker
- --addon NAME before --addon-run COMMAND

You can always run ```k8s-on-lxd.sh -h``` to get a short usage information


## One time setup

One-time .... per Kubernetes version you want to use.

First, you need to run the setup part. Expect to have ```sudo``` requesting the password for some root only actions.

Let's get a look at the options/commands it can handle:
```./k8s-on-lxd.sh --help```

Let's run the one-time setup phase. Can take some time (minutes)
```./k8s-on-lxd.sh --setup```

Important: double check what version it will install. You can force a specific version, by using ```--k8s-version X.Y.Z``` Please note that the revision part ("Z") of the version might not be the exact one installed.

On the reference desktop, it takes 6-7 minutes to have the images ready.

Note that because the script brings in the docker images used for Kubernete's control plane (Apiserver, etcd, and so on), the image size will be quite big: 1.2-1.7Gb

If you want to speed things up - you could try to copy first the images built by you/friend from a different LXD remote and then run the setup. Something like:

```bash
lxc image copy --copy-aliases friend-computer:k8s-1-18-2-worker local:
lxc image copy --copy-aliases friend-computer:k8s-1-18-2-master local:
./k8s-on-lxd.sh --setup
```



## Creating a cluster
### Master node

Let's start a new 'cluster' named 't2'. We start by creating the master node
```./k8s-on-lxd.sh --name t2 --master```

After 1 minute and 42 seconds, I got it ready. *kubectl* is also setup to use it:
```bash
kubectl --context lxd-t2 get node                                        
NAME        STATUS   ROLES    AGE     VERSION
t2-master   Ready    master   2m31s   v1.18.2
```
Note that script waits for the node to be declared 'Ready' (which took ~35 seconds).

Context  names are of the form ```lxd-NAME``` . Pods will not be deployed on the master node, unless you play with its labels.
You should double check things are ok - one good way is to check all control plane pods are 'Running'. 

```bash
kubectl --context lxd-t2 get pod --all-namespaces 
NAMESPACE     NAME                                READY   STATUS    RESTARTS   AGE
kube-system   coredns-66bff467f8-2g92b            1/1     Running   0          2m41s
kube-system   etcd-t2-master                      1/1     Running   0          2m48s
kube-system   kube-apiserver-t2-master            1/1     Running   0          2m48s
kube-system   kube-controller-manager-t2-master   1/1     Running   0          2m47s
kube-system   kube-flannel-ds-amd64-lccdj         1/1     Running   0          2m40s
kube-system   kube-proxy-c48n7                    1/1     Running   0          2m40s
kube-system   kube-scheduler-t2-master            1/1     Running   0          2m47s
                                                                                     
```

There shouldn't be errored pods, all should end up being in 'Running' state

You can also see the started lxd container - its name is 't2-master', by running ```lxc list```



### Adding worker nodes

Let's add one 'worker' node 
```./k8s-on-lxd.sh --name t2 --worker```
This time, no need to say which kubernetes version, it will know it. After ~1m12s I got it 'Ready'.
Check again the lxd containers, now we also have 't2-worker-1' (run ```lxc list```)
Let's see the Kubernetes nodes:

```bash
kubectl --context lxd-t2 get node
NAME          STATUS   ROLES    AGE     VERSION
t2-master     Ready    master   6m47s   v1.18.2
t2-worker-1   Ready    <none>   2m9s    v1.18.2
```

And, again, check the pods:
```kubectl --context lxd-t2 get pod --all-namespaces```

And, for multi node cluster, add one more node:
```bash
./k8s-on-lxd.sh --name t2 --worker
lxc list
kubectl --context lxd-t2 get node
```
Of course, you can add more if you want, as long as your physical machine is allowing you :)

### Removing a worker node

If you want to remove a node:

a) follow standard kubectl procedure to drain node. One possible example:

```bash
kubectl --context lxd-t3 drain t3-worker-2 --ignore-daemonsets
kubectl --context lxd-t3 delete node t3-worker-2
kubectl --context lxd-t3 get nodes
# that t3-worker-2 node should not appear anymore
```

And now you can just delete the node machine, that is, the LXD container:

```bash
lxc stop t3-worker-2
lxc delete t3-worker-2
```



## Stopping the cluster

This means just stopping the LXD containers. Maybe you switch to another cluster or you just take a pause.

```k8s-on-lxd.sh --name NAME --stop```

On an empty cluster (just with Kubernetes Dashboard addon), with 2 worker nodes, it took a few seconds.



## Starting back the cluster

```k8s-on-lxd.sh --name NAME --run```

Same kindof' empty cluster, with 2 worker nodes: containers started in 2 seconds, pods where running in another 10 seconds.

**Important**: LXD will automatically start your containers at machine reboot. In case you have problems with the cluster, something might have changed in your environment but was not reflected into your cluster - usually a proxy.

Stop and then start all your containers, via the '--stop' and '--run' commands.

During the start process, addons might run some functions. For example, the 'proxy' addon will update the environment in your container to 
reflect your host proxy environment variables. If your container was started by LXD, it will not get a chance to have the proxies updated, so it might not reach the other nodes or external internet.


## Removing the cluster

First you stop it, via ```--stop``` then you 
```
k8s-on-lxd.sh --name NAME --delete
```

---
# Remote LXD servers
There is support for using a remote LXD server.
Steps:
- you need to run the '--setup' phase directly on that LXD server.
- add your remote: ```lxd remote add SomeName theRemoteAddressAndPort```
- then you can use the same commands but add ```--remote NameOfTheRemote```. Example:
  ```k8s-on-lxd.sh --remote dorel --name home-dev1 --master```
- LXD container IPs are local to the machine - including the master API entry point.
  In order to have access to it, remotely, with kubectl, a LXD proxy device will be set on a random port.
- some checks during might be disabled (check for swap, or for enough disk space)

---

# Accessing your services
For that, we're going to use Proxy's feature of LXD.
https://github.com/lxc/lxd/blob/master/doc/containers.md#type-proxy

For example, the Kubernetes Dashboard is using this to allow you to easily get to the Web UI

---


# Addons
These add functionality during normal script runs (like 'proxy-cache' addon), or on user's request  - like 'dashboard' addon.
To use them, you speficy the addon: ```--addon dashboard``` for example, and what to do: ```--addon-run add```

To get list of addons:
​```--addon-list```

To get information about an addon:
​```--addon NAME --addon-info```
Usually the addon will display what it does and how to run it.

For example, the Kubernetes Dashboard addon provides commands like 'add', 'remove', 'show-token', 'access':

```k8s-on-lxd.sh --name NAME --addon dashboard --addon-run access```

NOTE: for the moment, "--addon-run" should be the last parameter in the command line.

See the documentation for each addon in its own directory *addons/NAME/README.md*

List:
- [addons/proxy-cache/README.md](addons/proxy-cache/README.md) - ensure things are setup so that the installation uses your proxy 
- [addons/dashboard/README.md](addons/dashboard/README.md) - installs Kubernetes Dashboard Web UI
- [addons/apt-proxy-cache/README.md](addons/apt-proxy-cache/README.md) - during setup phases, uses APT proxy from environment variable  *apt_proxy_cache*
- [addons/local-storage-class/README.md](addons/local-storage-class/README.md) - Local host storage class. Read [storage](docs/storage.md) first.
- [addons/nfs-client-provisioner/README.md](addons/nfs-client-provisioner/README.md) - NFS provisioned storage class. Read [storage](docs/storage.md) first.
- [addons/letsencrypt-staging/README.md](addons/letsencrypt-staging/README.md) - Add Letsencrypt *Staging* certificate inside the nodes

---
# Development
See [docs/DEV.md](docs/DEV.md)

