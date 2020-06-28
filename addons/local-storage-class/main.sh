#shellcheck shell=bash

# for https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner
# it double checks, ONLY at pod startup for mounted directories in
# /mnt/STORAGECLASS/
#
# Other notes:
# if you create directories AFTER pod is running, you need to kill it because it will not see the new mounts
# and it will display you an 'is not an actual mountpoint'
#

ADDON_LOCAL_STORAGE_CLASS_NAME="Local storage provisioner"
addon_local_storage_class_dir=""
addon_local_storage_class_name="local-disks"
ADDON_LOCAL_STORAGE_CLASS_COUNT_VOLUMES_PER_NODE=20

addon_local_storage_class_info() {
    cat <<EOS

$ADDON_LOCAL_STORAGE_CLASS_NAME : by adding this addon, you will get a storage class named 
    'local-disks' (or the name you choose), that will map to directories on your local machine. 

To add it:
k8s-on-lxd.sh --addon local-storage-class --name CLUSTER_NAME --dir DIRECTORY_ON_YOUR_HOST --addon-run add    
For remote LXD nodes, '--dir' will be ignored.

The storage class is by default 'local-disks' but you can change it, when adding this, via
    --class className
EOS
}

addon_local_storage_class_parse_arg() {
    if [ "$1" == "--dir" ]; then
        checkArg "$1" "$2"
        addon_local_storage_class_dir="$2"
        #shellcheck disable=SC2034
        processedArgumentsCount=2
    fi    
    if [ "$1" == "--class" ]; then
        checkArg "$1" "$2"
        addon_local_storage_class_name="$2"
        #shellcheck disable=SC2034
        processedArgumentsCount=2
    fi    
}

ensure_addon_local_storage_class_dir_is_set() {
    lxdRemoteIsLocal || return 0
    if [ -z "$addon_local_storage_class_dir" ]; then
        # check if it is set in the master's config
        addon_local_storage_class_dir=$(lxc config get "$LXD_REMOTE${CLUSTER_NAME}-master" user.local_storage_class.dir)
        if [ -z "$addon_local_storage_class_dir" ]; then
            bail "Please let me know where the storage on the host should be, via: --dir PATH"
        fi
    fi
}


addon_local_storage_class_enabled() {
    runKubectl get daemonset -n default -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'  | grep -qE '^local-volume-provisioner$'
}

_addon_local_storage_class_yaml_file() {
    echo "$SCRIPT_PATH/addons/local-storage-class/deployment.yaml"
}

addon_local_storage_class_add() {
    ensureClusterNameIsSet


    #if addon_local_storage_class_enabled ; then
    #    bail  "It looks like addon '$ADDON_LOCAL_STORAGE_CLASS_NAME' is already added"
    #fi

    if lxdRemoteIsLocal; then
        ensure_addon_local_storage_class_dir_is_set

        info "Adding $ADDON_LOCAL_STORAGE_CLASS_NAME, with storage path '$addon_local_storage_class_dir'"

        test -d "$addon_local_storage_class_dir" || mkdir -p "$addon_local_storage_class_dir"

        lxc config set "$LXD_REMOTE${CLUSTER_NAME}-master" user.local_storage_class.dir "$addon_local_storage_class_dir"
    else
        info "Adding $ADDON_LOCAL_STORAGE_CLASS_NAME"
    fi
    addon_local_storage_class_prepare_dirs
    
    sed -E -e "s@\\$\{CLASS_NAME\}@$addon_local_storage_class_name@" "$(_addon_local_storage_class_yaml_file)" | runKubectl apply -f -
}

addon_local_storage_class_prepare_dirs() {
    ensureClusterNameIsSet

    ensure_addon_local_storage_class_dir_is_set

    for c in $(lxcListByPrefixAllWorkers "$CLUSTER_NAME") ; do
        _addon_local_storage_class_prepare_container "$c" "$addon_local_storage_class_dir"
    done
}


_addon_local_storage_class_prepare_container() {
    local container=$1
    local addon_local_storage_class_dir=$2
    
    info "Preparing container '$container' for addon '$ADDON_LOCAL_STORAGE_CLASS_NAME'"
        
    if lxdRemoteIsLocal; then
        for i in $(seq -w 1 $ADDON_LOCAL_STORAGE_CLASS_COUNT_VOLUMES_PER_NODE); do
            local d="$addon_local_storage_class_dir/$container/$i"
            test -d "$d" || mkdir -p "$d"
        done

        local existing_dir
        existing_dir=$(lxc query "$LXD_REMOTE/1.0/containers/$container" | jq -r '.devices["host-storage"].source' || true)
        [ "$existing_dir" = "null" ] && existing_dir=""
        
        local data_dir="$addon_local_storage_class_dir/$container/"

        if [ "$existing_dir" != "$data_dir" ]; then
            if [ -n "$existing_dir" ]; then
                lxc config device remove "$LXD_REMOTE$container" host-storage
            fi
            lxc config device add "$LXD_REMOTE$container" host-storage disk source="$data_dir" path=/mnt/host-storage
        fi
        
    fi


    # DO NOT forget to backquote $
    lxcExecBashCommands "$container" <<EOS    
for i in \`seq -w 1 $ADDON_LOCAL_STORAGE_CLASS_COUNT_VOLUMES_PER_NODE\` ; do
        ds="/mnt/host-storage/\$i"
        dd="/mnt/local-disks/\$i"

        test -d \$ds || mkdir -p \$ds
        test -d \$dd || mkdir -p \$dd
        fgrep -q \$dd /etc/fstab || echo "\$ds \$dd none bind" >> /etc/fstab
        mount \$dd
done
EOS

	#lxcExec $container cat /etc/fstab		    
}


# hook ourselves:
launch_worker__02_local_storage_class_setup() {
    local prefix=$1
    #local masterContainer=$2
    local container=$3

    addon_local_storage_class_enabled || return 0
    
    local addon_local_storage_class_dir
    addon_local_storage_class_dir=$(lxc config get "$LXD_REMOTE${prefix}-master" user.local_storage_class.dir)

    _addon_local_storage_class_prepare_container "$container" "$addon_local_storage_class_dir"
}


