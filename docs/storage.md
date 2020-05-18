# Storage in  Kubernetes 



You can also check this, if you want: https://kubernetes.io/docs/concepts/storage/

One very important part of an infrastructure, is its storage. Even in Kubernetes, storage is important.

Kubernetes offers storage as volumes from various [providers](https://kubernetes.io/docs/concepts/storage/volumes/#types-of-volumes). 

You can define the volumes per individual deployment, or, group the properties about the storage under **[storage classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)**, and then just use the storage class names - which makes it easier to work with it.



For the sake of explaining our storage addons, we'll try to say that storage types in kubernetes are having the following group of properties:

- a) ephemeral or not (data is removed or not after pod is stopped/moved somewhere else)

- b) it forces or not a specific node to a pod when first created

- c) it forces or not a specific node when pod is **re**created

- d) storage is local to a node or not

  

  Examples:

  | Name                                         | Ephemeral? | Forced node @first                | Forced node @later                | Local2Node     |
  | -------------------------------------------- | ---------- | --------------------------------- | --------------------------------- | -------------- |
  | awsElasticBlockStore, cephfs, glusterfs, nfs | no         | no                                | no                                | no             |
  | emptyDir                                     | yes        | no                                | no                                | yes            |
  | hostPath                                     | no         | no (but **you** probably want it) | no (but **you** probably want it) | yes            |
  | local                                        | no         | no                                | yes                               | yes            |
  | Our addons:                                  |            |                                   |                                   |                |
  | local-storage-class                          | no         | no                                | yes                               | yes            |
  | nfs-client-provisioner                       | no         | no                                | no                                | yes, to master |
  
  

Each type of storage has its Pro and Cons, of course.

With your local LXD clusters you don't have limits on what to use, but to make it easier for you to start working on what is more important to you, we provide some storage addons.

If you want to get access to the data stored in *nodes* ('*Local2Node*' == yes), you either:

- enter the container and check it, 
- or, you can mount the directories from the nodes to your real host machine so that you don't need to run commands like ```lxc shell mysite-worker-2```  This is what [local-storage-class](../addons/local-storage-class/README.md) and [nfs-client-provisioner](../addons/nfs-client-provisioner/README.md) are doing.

