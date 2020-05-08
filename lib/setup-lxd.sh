# shellcheck shell=bash

# Setup LXD 
#

no_check_lost_found=""


setup_lxd__00_ensure_it_exists() {
    ensureLxdIsInstalled
}


setup_lxd__01_check_proxy_and_ubuntu_url() {
    #shellcheck disable=SC2154
    [ -n "$http_proxy" ] || return 0

    local url
    url=$(lxc remote list | grep -E '\subuntu\s' | cut -f 3 -d '|' | sed -E -e 's@ +@@gi')
    if [[ "$url" == "https:"* ]]; then
        warn "Looks like you're using a proxy. If it is also a caching proxy, to make things faster"
        warn "when downloading images you could change url to use http:// instead of https://"
        warn "for the lxd remote 'ubuntu', by using "
        warn "lxc remote set-url ubuntu ${url/https/http}"
    fi
}


# we need a 'dir' type storage
# also, lxd complains if it is not empty (and if it is a partition, there is a 'lost+found' dir in it)
setup_lxd__02_storage_dir_checks() {
    info "Checking for 'dir' type storage"

    local storage_name
    storage_name=$(lxdGetStoragePoolDirType)
    if [ -n "$storage_name" ]; then
        info "   found storage-pool named '$storage_name'"
        return 0
    fi

    # let's see where the default storage is created, to create near it
    local storage_base_dir
    storage_base_dir="$(lxc query '/1.0/storage-pools/default' 2>/dev/null | jq -r '.config.source')"
    if [ -z "$storage_base_dir" ]; then
        # no 'default' pool. Will take first one around.
        local url
        url=$(lxc query "/1.0/storage-pools" | jq -r '.[0]')
        storage_base_dir="$(lxc query "$url" 2>/dev/null | jq -r '.config.source')"

    fi
    storage_base_dir=$(dirname  "$storage_base_dir")

    local STORAGE_DIR_NAME=dir
    local DIR_STORAGE_BASE_DIR="$storage_base_dir/$STORAGE_DIR_NAME"

    if [ ! -d "$DIR_STORAGE_BASE_DIR" ]; then
        info "We'll want create directory '$DIR_STORAGE_BASE_DIR', via sudo. You might be asked for password"
        sudo mkdir -p "$DIR_STORAGE_BASE_DIR"
    fi

    if false && type -P btrfs &>/dev/null && btrfs "fi" df "$DIR_STORAGE_BASE_DIR" 2>/dev/null | grep -F -q 'Data,' ; then
        bail "$DIR_STORAGE_BASE_DIR seems to be a BTRFS filesystem. Not good."
    fi

    # TODO: zfs check
    
    # check if standard partition
    if [ -z "$no_check_lost_found" ] && [ -d "${DIR_STORAGE_BASE_DIR}/lost+found" ]; then
        bail "there is a lost+found directory in there (an ext3/ext4 partition)? Create a subdirectory and use that one. Or run with --no-check-lost-found"
    fi

    if false; then    
        # find out FS type by checking recursively the mount points of the directory/parents
        _=$DIR_STORAGE_BASE_DIR
        mountType=$(storage_dir_mount_info | sed -E "s/.* type (\S+).*/\1/")  
        if [ "$mountType" == "" ]; then
                bail "Could not determine type of filesystem at $DIR_STORAGE_BASE_DIR"
        fi
            
        if [ "$mountType" == "ext3" ] || [ "$mountType" == "ext4" ]; then
            info "      type $mountType. Cool"
        else
            bail "Unknown if mount type '$mountType' is ok with kubernetes inside LXD..."
        fi
    fi


    # check for a 'dir' named storage, of type 'dir'
    local dir_driver
    dir_driver=$(lxc query "/1.0/storage-pools/$STORAGE_DIR_NAME" 2>/dev/null | jq -r '.driver')
    if [ -n "$dir_driver" ]; then
        # present. Check parameters
        if [ "$dir_driver" != "dir" ]; then
            bail "Storage named $STORAGE_DIR_NAME present but not of type 'dir'"
        fi
        local path
        path=$(lxdGetStoragePoolPath "$STORAGE_DIR_NAME")
        if [ "$path" != "$DIR_STORAGE_BASE_DIR" ]; then
            bail "Storage named $STORAGE_DIR_NAME present but path is not $DIR_STORAGE_BASE_DIR"
        fi
        info "Storage $STORAGE_DIR_NAME of type 'dir' exists. Cool"
    else
        # storage does not exist. Create it
        info "Creating storage $STORAGE_DIR_NAME of type 'dir' from path $DIR_STORAGE_BASE_DIR"
        lxc storage create dir dir source="$DIR_STORAGE_BASE_DIR"
    fi
}


etc_subguid_setup() {
    f=$1

    info "Setting up ID mappings in $f"

    uid=$(id -u)
    uidName=$(id -u -n)

    subID=1000000
    #subIDCount=1000000000
    subIDCount=65536
    

    rootLine="root:${subID}:${subIDCount}"
    userLine="${uidName}:${subID}:${subIDCount}"
    if  [ ! -f "$f" ]; then 
        sudo bash -c "echo -e '${rootLine}\n\${userLine}n' >$f"
        return 0
    fi
    if ! grep -F -q "root:" "$f"; then
        sudo bash -c "echo '${rootLine}' >> $f"
    fi


#    if ! grep -P -q "${rootLine}" $f ; then
#        bail "in $f, we should have a line like $rootLine . Manually fix and restart lxd service"
#    fi
    if ! grep -P -q "^$uid:"  "$f" && ! grep -P -q "^$uidName:" "$f"; then
        sudo bash -c "echo '${userLine}' >> $f"
    fi
#    if ! fgrep -q "${userLine}" $f ; then
#        bail "in $f, we should have a line like $userLine . Manually fix and restart lxd service"
#    fi
}

setup_lxd__04_subuid() {
    etc_subguid_setup /etc/subuid
    etc_subguid_setup /etc/subgid
}


sysctl_updated=0

setup_lxd__10_sysctl_bridge_nf_call() {
    # TODO: double check it is still necessary
    # sysctlSet net.bridge.bridge-nf-call-iptables 1 || sysctl_updated=1

    true
}


setup_lxd__12_sysctl_fs_notify() {

    info "checking sysctl fs.notify.* values"


    # https://github.com/lxc/lxd/blob/master/doc/production-setup.md#etcsysctlconf
    sysctlSetIfTooSmall fs.inotify.max_queued_events 1048576 || sysctl_updated=1
    sysctlSetIfTooSmall fs.inotify.max_user_instances 1048576 || sysctl_updated=1
    sysctlSetIfTooSmall fs.inotify.max_user_watches 1048576 || sysctl_updated=1
}

setup_lxd__14_sysctl_others() {
    info "checking other sysctl settings"

    sysctlSetIfTooSmall vm.max_map_count 262144 || sysctl_updated=1
    sysctlSet kernel.dmesg_restrict 1 || sysctl_updated=1

    # not needed for a dev box :-)
    #sysctlSetIfTooSmall kernel.keys.maxkeys 2000 || sysctl_updated=1
}

setup_lxd__16_systctl_net() {
    info "checking sysctl net.* settings"


    sysctlSetIfTooSmall net.netfilter.nf_conntrack_buckets 32768 || sysctl_updated=1
     
    # not needed for a dev box :-)
    #sysctlSetIfTooSmall net.ipv4.neigh.default.gc_thresh3 8192 || sysctl_updated=1
    #sysctlSetIfTooSmall net.ipv6.neigh.default.gc_thresh3 8192 || sysctl_updated=1
}


setup_lxd__19_sysctl_update() {
    if [ "$sysctl_updated" = "1" ]; then
        info "sysctl changes done. Need to load them"
        sysctlLoadFile
    fi
}


setup_lxd__22_conntrack() {
    return 0 # doesn't seem, yet, to be needed
    info "checking for 'conntrack' program"
    checkForCommand conntrack
    # TODO: verify conntrack -L gives something (i.e. it works)
    # TODO: ensure xt_conntrack is loaded.    
}


__setup_lxd_network_device() {
    local name="$1"

    local url="/1.0/networks/$name"

    local cidr
    cidr=$(lxc query "$url" | jq -r '.config["ipv4.address"]')
    local dhcp_ranges
    dhcp_ranges=$(lxc query "$url" 2>/dev/null | jq -r '.config["ipv4.dhcp.ranges"]')

    # let's check on some simpler cases:
    if [[ "$cidr" == *".1/24" ]]; then
        local base
        base=$(echo "$cidr" | cut -d '.' -f 1-3)
        expected_dhcp_ranges="$base.50-$base.254"

        if [ "$dhcp_ranges" = "null" ]; then
            lxc network set "$name" ipv4.dhcp.ranges "$expected_dhcp_ranges"
            info "   used $expected_dhcp_ranges"
            return 0
        fi
        if [ "$dhcp_ranges" = "$expected_dhcp_ranges" ]; then
            info "    ... already set as expected ($dhcp_ranges)"
            return 0
        fi
        info " ... already set, but not exactly what we wanted: $dhcp_ranges vs wanted $expected_dhcp_ranges. Hoping for the best"
        return 0
    fi
    bail "Un uncommon/unhandled value for the the CIDR ipv4 address: $cidr. Please report."
}


setup_lxd__25_dhcp_range() {
    info "Setting up LXD DHCP range"

    local intf
    intf=$(lxdGetHostInterface)

    __setup_lxd_network_device "$intf"
}