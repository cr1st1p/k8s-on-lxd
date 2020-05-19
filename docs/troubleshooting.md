# Troubleshooting your setup
- [Your node fails to be declared ready](#your-node-fails-to-be-declared-ready)
- [Proxy](proxy)

## Your node fails to be declared ready
### When
In case ```k8s-on-lxd.sh --master | --worker``` ends in error with something like
```
After many tries, node is still not declared as ready. You should check the logs inside it.
```

### Check for free disk space
Minimal free disk space in the *important* place(s) should be 10-20%.
Important = where the container would be put by LXD and where kubernetes cluster would use for its own purposes.
Usually these "important" places are:
- the root directory (/)
- /var/lib/kubelet
- /var/lib/docker

Run on your computer a ```df -h```
Also, enter the container via an ```lxc shell CONTAINER``` and run in there ```df -h``` - this is better since it could show a lot less entries :-)

### Check logs
Enter container first.
Then try:
- journalctl
- less /var/log/syslog
- service kubelet status

### Check for failing containers
Enter container first. Then:
```kubelet --kubeconfig /etc/kubernetes/admin.conf get pod --all-namespaces```

Example of possible output:

```
root@cluster1-master:~# kubectl --kubeconfig /etc/kubernetes/admin.conf   get pod --all-namespaces
NAMESPACE     NAME                                      READY   STATUS                  RESTARTS   AGE
kube-system   coredns-66bff467f8-gnt9w                  0/1     Pending                 0          3m10s
kube-system   coredns-66bff467f8-jz495                  0/1     Pending                 0          3m10s
kube-system   etcd-cluster1-master                      1/1     Running                 0          3m22s
kube-system   kube-apiserver-cluster1-master            1/1     Running                 0          3m22s
kube-system   kube-controller-manager-cluster1-master   1/1     Running                 0          3m22s
kube-system   kube-flannel-ds-amd64-9hcp7               0/1     Init:ImagePullBackOff   0          3m11s
kube-system   kube-proxy-8qjqx                          1/1     Running                 0          3m11s
kube-system   kube-scheduler-cluster1-master            1/1     Running                 0          3m22s
```
Note: the pending *coredns* pods are ok for now - they don't have an available **worker** node to run on.
But, you see that kube-flannel had some problems.

Let's see what's up with that pod:
```
root@cluster1-master:~# kubectl --kubeconfig /etc/kubernetes/admin.conf   describe pod kube-flannel-ds-amd64-9hcp7 -n kube-system
Name:         kube-flannel-ds-amd64-9hcp7
Namespace:    kube-system
Priority:     0
Node:         cluster1-master/10.207.127.3
Start Time:   Tue, 19 May 2020 10:47:26 +0000

....
  Normal   Pulling    94s (x4 over 3m28s)  kubelet, cluster1-master  Pulling image "quay.io/coreos/flannel:v0.12.0-amd64"
  Warning  Failed     93s (x3 over 3m25s)  kubelet, cluster1-master  Failed to pull image "quay.io/coreos/flannel:v0.12.0-amd64": rpc error: code = Unknown desc = Error response from daemon: Get https://quay.io/v2/coreos/flannel/manifests/v0.12.0-amd64: received unexpected HTTP status: 500 Internal Server Error
  Warning  Failed     93s (x4 over 3m25s)  kubelet, cluster1-master  Error: ErrImagePull
  Warning  Failed     81s (x6 over 3m24s)  kubelet, cluster1-master  Error: ImagePullBackOff
  Normal   BackOff    66s (x7 over 3m24s)  kubelet, cluster1-master  Back-off pulling image "quay.io/coreos/flannel:v0.12.0-amd64"
```

Hm, so it failed to download the image?!? Indeed, I got "lucky" and RedHat's quay.io had a temporary partial outage during this test, but at least I had a real life example to show you :-)

### Check that the minimal number of pods are running
Run inside the container:
```shell
root@cluster1-master:~# kubectl --kubeconfig /etc/kubernetes/admin.conf   get pod --all-namespaces
```
You should find running pods for:
- etcd
- kube-apiserver
- kube-controller-manager
- kube-flannel
- kube-proxuy
- kube-scheduler

For example, at some point I could not find kube-flannel. I found out that it was because of incompatible versions of deployment manifest for that
particular kubernetes version.



## Proxy
The script has an addon that is detecting and handling you using a proxy. 
But issues could still pop up here and there, so the addon will give you some warnings
and specific instruction on what to pay attention to.

For example, depending where the proxy is running, it might not see your LXD containers due to networking. So you have to ensure your *kubectl* commands are not using it, for example.

There are 2 ways:
- add to the **no_proxy** environment variable the while CIDR range of your LXD containers, so that (some) programs will NOT use the proxy for those targets. I'm saying "some" because that environment variable and format is not very standardized.
- unset **http_proxy** for when you run kubectl/whatever program:
```shell
http_proxy= https_proxy= kubectl --context lxd-my-second-cluster ....
```
