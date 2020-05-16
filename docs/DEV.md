# General
Lot of Bash shell code, extensible via running functions with specific prefix names.

Flow is:
- setup host
- setup LXD
- setup a specific LXD profile
- setup LXD image containers to be used later as starting images:
-- setup a common LXD container and converting into an image
-- setup a lxd master container based on the common one, and converting to image
-- setup a lxd worker container based on the common one, and converting to image
-- common image is deleted

LXD Images are created per Kubernetes version.

After that, whenever a new master or worker is created, it will be just launched from the pre-built image.

When creating a master node:
- appropriate base LXD master image is selected
- launch functions are called
- specific post launch messages are displayed

Simialr for a worker machine.
Note though that to not enter various issues with reusing worker node names (like if you delete and then create a new worker node),
whenever a new worker machine is created, a new index value will given to it.

Some settings are stored inside the master's container configuration, where they are taken by code to launch new workers or by addons.


# Functionality groups calling

There are groups of functions run via 'runFunctions'.
They serve various purposes and it allows for expanding the functionality.

"runFunction" will check all existing bash functions defined starting with the specified prefix, and then
run them in lexicographical order.

---
# Groups of functions (by prefix)
## setup_host
All kinds of setup of your Linux host machine.
Kernel module settings, sysctl, etc.

## setup_lxd
Ensures 'lxd' is installed and a few settings related to its correct functioning

## lxd_profile_create
Functions used to setup the profile that will be used with all the containers.
Name of profile is given by global variable LXD_PROFILE_NAME


---
## Preparing LXD images
A master and a worker nodes are mostly identical, but master has more docker images in it that it will need to run.
Code will build first a commong image, after which, based on that common image, it will build separate ones for the master 
and slave.
Creation of the images is happening by setting up some containers and then creating LXD images from them.


### prepareLxdImage
Called to prepare the initial common LXD image. 

### insideLxdImage
Part of the preparation of the initial common LXD image, but these functions will be run *inside* the container.

### prepareLxdImage_master
called to prepare a LXD master image, based on the common image built in previous steps

### insideLxdImage_master
Pare of the preparation of a master image, but these are run *inside* the master container (that will later be converted to an image)

Called by ```prepareLxdImage_master__30_inside_script_run```

For example, used to:
- pull specific container images


### prepareLxdImage_worker
called to prepare a LXD master image, based on the common image built in previous steps

### insideLxdImage_worker
Pare of the preparation of a worker image, but these are run *inside* the master container (that will later be converted to an image)

Called by ```prepareLxdImage_worker__30_inside_script_run```

For example, used to:
- install nfs client
- pull specific container images


### prepareLxdImageCleanup
called to cleanup a master or worker container that will be converted in LXD images

That is, flows will be:
A: prepareLxdImage_master + insideLxdImage_master + prepareLxdImageCleanup + convert to image
B: prepareLxdImage_worker + insideLxdImage_worker + prepareLxdImageCleanup + convert to image


---

## launch_master
Called to create and start a new master. After it starts, messages will be displayed, by calling `messages_master_node__` set of functions - see below

## launch_worker
Called to create and start a new worker. After it starts, messages will be displayed, by calling `messages_worker_node__` set of functions - see below
There is a counter used so that new workers will always get a new, linearly increasing id.

## init_before_master_starts__
Called one time, when a master node is created. After creating the container (stopped state!) and before calling the 'before_node_starts__' hooks and the rest of setup with the container running.

## init_before_worker_starts__
Similar as above but for a worker node.

## before_node_starts__
Run everytime a node starts. Be it the first time when it is created (and before full setup!) 
or everytime user wants the node to be started on demand.

----
## messages_master_node
Show messages to the user, after a master node is started

## messages_worker_node
Show messages to the user, after a worker node is started



--- 
# Addons
Code is inside the subdirectory ```addons/```. It should consists in at least the file ```main.sh```
That 'main.sh' file will be loaded during script startup phases.

An addon can have functions that are named according to the rules above, in case it needs to hook up into various flows.
For example, the 'proxy-cache' addon has a function like 'prepareLxdImage__10_01_global_http_proxy' meaning that the function
will be called during preparation of the "common" LXD container/image.

An addon can also define a function to be able to parse specific addon parameters - see addon *local-storage-class* for example.
The name of the function is of the form 'addon_${addon}_parse_arg`

An addon must implement an 'info' function that will display what it does and what user could call to set it up.
Function name is "addon_${addon}_info"
User will be able to see it like this:
```shell
k8s-on-lxd.sh --addon local-storage-class --addon-info
```


Besides hooking into the overall system, addons will implement functionality for the user - user will call it like:
```shell
k8s-on-lxd.sh --addon local-storage-class --name CLUSTER_NAME --dir DIRECTORY_ON_YOUR_HOST --addon-run add 
```
Above, the user wants to run the 'add' functionality of that addon named 'local-storage-class'
Note also the presence of the '--dir' parameter which is a parameter specific to that addon.

Internally, for a command COMMAND, for addon ADDON, the function 
'addon_${ADDON}_${COMMAND}" will be called.


An addon can store some settings in the master container configuration.
Example:
```
v=$(lxc config get "${CLUSTER_NAME}-master" user.letsencrypt_staging.install_cert)
```

Or it can check what is present already inside the cluster:
```
runKubectl get daemonset -n default -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'  | grep -qE '^local-volume-provisioner$'
```
