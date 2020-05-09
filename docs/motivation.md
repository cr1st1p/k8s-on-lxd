NOTE: This script was started some longer time ago, things might have changed meanwhile. Please let me know.

It started when I needed to run a kubernetes cluster locally, on my machine, for developing purposes. And then I needed to have two of them, for two different purposes. 
One of them should have multiple nodes if possible - in order to test some HA setup.
Later on, having also different kubernetes versions was also wanted.


It started as a medium sized shell script, and ended into a multi-file shell script, with addons.

## Local environments setups
### kubeadm

Running directly ```kubeadm``` would mean a single node, single environment. 

Pro: Directly on your machine (lightweight)
Con: No multiple nodes; no multiple environments; no multiple k8s versions

On the other hand, it is such a good tool that I ended using it for my bare metal installs and for this script. Also, some of the other setups listed below are also using it.


### minikube
Tried ```minikube``` and while it worked, it did not have those 2 features I wanted, and, 
even more importantly, sometimes cpu went crazy for long times. Most probably because of
the underlying VM (I think it was virtualbox) and not an issue with minikube itself.

During my own tests of my script, running inside virtualbox, cpu as well spiked often for no obvious reasons, increasing my desire to not use a full blown virtual machine.

Pro:
- fully isolated. But actually depends on the vmdriver used? (Not sure that was there when I started this script)
- seems to allow choosing k8s version
- multiple container runtimes
Con: 
- cpu intensive for no obvious reason. When I used it with virtualbox
- not multi node
- no multiple environments running in the same time

### Lxd ?
Also - I thought - why a full blown VM? There is [LXD](https://linuxcontainers.org/lxd/introduction/) which I love and use for some years already. It makes development and testing way more enjoyable. Environment starts and stops in mere seconds. I also had such containers in production.

#### juju 
After thinking about LXD, I tried ```juju``` charm to install kubernetes inside LXD. Tried several times. It succeeded to install it only one time, after maaaany minutes, but after that it had also quite some big cpu load. Most of the time, it did not succeed to install at all, after tens of minutes. 

Issues could have coming from me having btrfs and zfs file systems. Because after digging around I found out that I have to avoid such filesystems for kubernetes inside LXD.

Besides the fact that most of the time it did not work, when it worked it took a long time to run (not good for an enjoyable development environment) + quite high cpu load + having to install juju and running it all the time for what seemed to be a one time setup... seemed overkill. 

Pro:
- theoretically lightweight, if you don't consider juju's own cpu load (non-negligible)
- can use multiple nodes

Con:
- it didn't succeeded most of the times
Unknown:
- multiple k8s version support?
- multiple simultaneous clusters? Probably yes.

### microk8s
Seems to run directly on your host OS. That means fast, but probably without isolation.
Pro:
- lightweight
- can select k8s version. 

Con:
- no multiple versions in the same time.
- no multi node
- no multiple environments
- need to research, but at first check: can't stop it from running **and** staying stopped (that is, after a reboot it starts again)
- I need 'root' for some of the common actions, like 'start', 'stop'

### kind
Not checked yet, but I don't think it fulfills at least the multi-node feature

### k3s
Not checked yet, but I don't think it fulfills the multi-node and multiple clusters feature.

### this shell script
- lightweight - it uses LXD system containers, which are not a heavy on your machine. Of course, slightly heavier than a direct kubeadm install, microk8s and maybe k3s.
- you can have multiple nodes (one master and N worker nodes)
- easy to start/stop. And once stopped, they do not consume memory or cpu at all. Unlike Juju, microk8s maybe.
- multiple clusters
- clusters can have different versions of kubernetes
