This addon will add [NFS](https://en.wikipedia.org/wiki/Network_File_System) based storage class provisioner.
It is installing https://github.com/kubernetes-incubator/external-storage/tree/master/nfs-client

See first a very short introduction to [storage](../../docs/storage.md).
Short list of characteristics as per the [storage](../../docs/storage.md) document: 

- ephemeral storage: no
- Pod is forced to a specific node when initially created: **no**
- Pod is forced, when recreated to a specific node: **no**
- storage is local to where the pod runs: no. It is local to master, and mounted from your host machine.

For your local development needs, you might not have a simple way to add a more complex storage solution (Ceph, Gluster, AWS, etc), but you would still want
to have something that is **automatically** provisioned, by the way of a **storageClass**, and **without** forcing pods on one node (unlike [local-storage-class](../local-storage-class/README.md)).


Internal notes:
deployment.yaml is the output of
ddk8s run --repo ddk8s --project nfs-client-provisioner  --namespace nfs-client-provisioner --set nfs.path=/mnt/nfs-export --set storageClass.reclaimPolicy=Retain --set nfs.server=NFS_SERVER_REPLACE_ME
