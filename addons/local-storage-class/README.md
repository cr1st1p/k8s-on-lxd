This addon will add a 'local' host storage provisioner.



See first a very short introduction to [storage](../../docs/storage.md), to understand what this addon is offering , and/or https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner



You can think of this addon offering you [local](https://kubernetes.io/docs/concepts/storage/volumes/#local) volumes but in an easy to consume form - via a storage class.

Short list of characteristics as per the [storage](../../docs/storage.md) document: 

- ephemeral storage: no

- Pod is forced to a specific node when initially created: **no** (pending conditions that storage is available)

- Pod is forced, when recreated to a specific node: **yes** (to the node where the storage was initially assigned)

- storage is local to where the pod runs: yes

  

Each Kubernetes node will have some fictive disks mounted, which will be presented to Kubernetes application under a specific storage class name. Each of those fictive disks will be actual directories on your host machine - using LXD features.

For example, you could set it so that under your **host**'s directory ```my_project/data/``` it will create a subdirectory for each kubernetes node, and inside those, a number of subdirectories (20 by default). Each such unused subdirectory will be selected by the provisioner whenever your deployment will ask for a storage with class 'local-disks'.

