#shellcheck shell=bash


ADDON_NFS_CLIENT_PROVISIONER_NAME="NFS client storage provisioner"
addon_nfs_client_provisioner_dir=""

addon_nfs_client_provisioner_info() {
    cat <<EOS

$ADDON_NFS_CLIENT_PROVISIONER_NAME : by adding this addon, you will get a storage class named 
    'nfs-client', which will be served by a NFS server, running on the master node. 
    Compared to 'local-storage-class', this one will not force a pod to any node.
    Master node's NFS directory will be mounted on your local host for easy access to your data.

To add it:
k8s-on-lxd.sh --addon nfs-client-provisioner --name CLUSTER_NAME --dir DIRECTORY_ON_YOUR_HOST --addon-run add

To remove it:
k8s-on-lxd.sh --addon nfs-client-provisioner --name CLUSTER_NAME --addon-run remove

After you add it, you can also try adding a very simple nginx server that would serve content from a volume
provisioned by this:
k8s-on-lxd.sh --addon nfs-client-provisioner --name CLUSTER_NAME --addon-run add-test

EOS
}

addon_nfs_client_provisioner_parse_arg() {
    if [ "$1" == "--dir" ]; then
        checkArg "$1" "$2"
        addon_nfs_client_provisioner_dir="$2"
        #shellcheck disable=SC2034
        processedArgumentsCount=2
    fi    
}

ensure_addon_nfs_client_provisioner_dir_is_set() {
    if [ -z "$addon_nfs_client_provisioner_dir" ]; then
        # check if it is set in the master's config
        addon_nfs_client_provisioner_dir=$(lxc config get "$LXD_REMOTE${CLUSTER_NAME}-master" user.nfs_client_provisioner.dir)
        if [ -z "$addon_nfs_client_provisioner_dir" ]; then
            bail "Please let me know where the storage on the host should be, via: --dir PATH"
        fi
    fi
}


addon_nfs_client_provisioner_added() {
    runKubectl get deployment nfs-client-provisioner -n nfs-client-provisioner &>/dev/null
}

addon_nfs_client_provisioner_add() {
    ensureClusterNameIsSet

    #if addon_nfs_client_provisioner_enabled ; then
    #    bail  "It looks like addon '$ADDON_NFS_CLIENT_PROVISIONER_NAME' is already added"
    #fi

    ensure_addon_nfs_client_provisioner_dir_is_set

    info "Adding $ADDON_NFS_CLIENT_PROVISIONER_NAME, with storage path '$addon_nfs_client_provisioner_dir'"

    test -d "$addon_nfs_client_provisioner_dir" || mkdir -p "$addon_nfs_client_provisioner_dir"

    local master="${CLUSTER_NAME}-master"

    lxc config set "$LXD_REMOTE$master" user.nfs_client_provisioner.dir "$addon_nfs_client_provisioner_dir"
    
    _addon_nfs_client_provisioner_prepare_master_container "$master" "$addon_nfs_client_provisioner_dir"

    _addon_nfs_client_provisioner_apply_deployment "$master" "apply"
}


_addon_nfs_client_provisioner_apply_deployment() {
    local master="$1"

    local master_ip
    master_ip=$(lxdGetConfiguredIp "$master")
    [ -n "$master_ip" ] || bail "Expected $master container to have a fixed IP!?"

    # load deployment
    local d="$SCRIPT_PATH/addons/nfs-client-provisioner"

    runKubectl apply -f "$d/namespace.yaml"

    sed -E -e "s@NFS_SERVER_REPLACE_ME@$master_ip@" "$d/deployment.yaml" | runKubectl apply -f -
}


_addon_nfs_client_provisioner_prepare_master_container() {
    local container="$1"
    local data_dir="$2"
    
    info "Preparing container '$container' for addon '$ADDON_NFS_CLIENT_PROVISIONER_NAME'"

    local intf
    intf=$(lxdGetHostInterface)

    # let's find a suitable unused IP. Assuming we set LXD's dhcp to leave some available
    local url="/1.0/networks/$intf"
    local cidr
    cidr=$(lxc query "$LXD_REMOTE$url" | jq -r '.config["ipv4.address"]')

    # DO NOT forget to backquote $
    lxcExecBashCommands "$container" <<EOS
source /usr/local/lib/shell/general.sh    
source /usr/local/lib/shell/apt.sh    

apt_update_now
apt_install nfs-kernel-server

d="/mnt/nfs-export"
test -d "\$d" || mkdir -p "\$d"
chmod 777 "\$d"

if ! grep -q '/mnt/nfs-export' /etc/exports; then
    echo "/mnt/nfs-export 10.244.0.1/24(fsid=20,rw,crossmnt,no_root_squash,anonuid=1001,anongid=1001,async,no_subtree_check) $cidr(fsid=21,rw,crossmnt,no_root_squash,anonuid=1001,anongid=1001,async,no_subtree_check)" >> /etc/exports
fi

exportfs -a
EOS


    local existing_dir
    existing_dir=$(lxc query "$LXD_REMOTE/1.0/containers/$container" | jq -r '.devices["nfs-host-storage"].source' || true)
    [ "$existing_dir" = "null" ] && existing_dir=""
    
    if [ "$existing_dir" != "$data_dir" ]; then
        if [ -n "$existing_dir" ]; then
            lxc config device remove "$LXD_REMOTE$container" nfs-host-storage
        fi
        lxc config device add "$LXD_REMOTE$container" nfs-host-storage disk source="$data_dir" path=/mnt/nfs-export
    fi

	#lxcExec $container cat /etc/fstab		    
}

addon_nfs_client_provisioner_add_test() {
    if ! addon_nfs_client_provisioner_added; then
        bail "You need to add first this addon"
    fi

    local d="$SCRIPT_PATH/addons/nfs-client-provisioner"
    runKubectl apply -f "$d/demo.yaml"

    local NAME=nginx-nfs-client-test
    addServiceProxy "default" "$NAME"

    ensure_addon_nfs_client_provisioner_dir_is_set


    cat <<EOS
Reminder: the data directory on your host is: 
  $addon_nfs_client_provisioner_dir

Wait for the nginx pod ($NAME) to be running, then check the PersistentVolumeClaim '$NAME'
and see the name of its bounded PV. 
Then, you should find the directory with the data, as 
    $addon_nfs_client_provisioner_dir/default-$NAME-PVNAME

And you can start by writing a simple content like
    echo "Welcome!" > $addon_nfs_client_provisioner_dir/default-$NAME-PVNAME/index.html

And load the content in your browser by accessing  the http links from above.
EOS
}


addon_nfs_client_provisioner_remove() {
    ensureClusterNameIsSet

    info "Removing addon '$ADDON_NFS_CLIENT_PROVISIONER_NAME'. Ignore errors related to NotFound resources."

    local master="${CLUSTER_NAME}-master"

    # remove the test, if installed
    local d="$SCRIPT_PATH/addons/nfs-client-provisioner"
    runKubectl delete -f "$d/demo.yaml" || true
    removeServiceProxy "default" "nginx-nfs-client-test" || true

    runKubectl delete --ignore-not-found=true -f "$d/namespace.yaml"

    lxcExecBashCommands "$master" <<EOS
if test -f /etc/exports && grep -q /mnt/nfs-export /etc/exports; then
    sed -i -E -e 's@/mnt/nfs-export.*@@' /etc/exports || true
    exportfs -a
fi
EOS

    local host_dir
    host_dir=$(lxc config get "$LXD_REMOTE$master" user.nfs_client_provisioner.dir 2>/dev/null || true)
    if [ -n "$host_dir" ]; then
        lxc config unset "$LXD_REMOTE$master" user.nfs_client_provisioner.dir || true
    fi

    local disk
    disk=$(lxc query "$LXD_REMOTE/1.0/containers/$master" | jq -r '.devices["nfs-host-storage"].type' || true)
    if [ "$disk" = "disk" ]; then
        lxc config device remove "$LXD_REMOTE$master" nfs-host-storage || true
    fi
    
}
