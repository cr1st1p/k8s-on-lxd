This addon will add a 'local host' storage provisioner.

See https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner

That is, each Kubernetes node will have some fictive disks mounted, which will be presented to Kubernetes application
under a specific storage class name. Each of thos fictive disks will be actual directories on your host machine.

For example, you could set it so that under your host's directory ```my_project/data/``` it will create a subdirectory for 
each kubernetes node, and inside those, a number of subdirectories (20). Each such unused subdirectory will be selected by the provisioner whenever your deployment will ask for a storage with class 'local-disks'.

One import thing: being 'host local storage' means that:
- initially, kubernetes will choose whatever node for your pod (with free storage of course)
- later on, pod will always be scheduled to be run on the same node - i.e. it will follow the location of the storage directory
  
Read more on https://kubernetes.io/docs/concepts/storage/volumes/#local 

