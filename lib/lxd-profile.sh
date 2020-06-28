# shellcheck shell=bash
#
# Functions related to setting up a dedicated LXD profile
#
# needs:
# variable LXD_PROFILE_NAME to be set; 
# + general.sh already loaded


VERSION_FIELD="user.k8s.version"

lxd_profile_create__00_create_it() {
    lxc profile create "$LXD_REMOTE$LXD_PROFILE_NAME"    
    lxc profile set "$LXD_REMOTE$LXD_PROFILE_NAME" "$VERSION_FIELD" "$VERSION"
}

# This will tell guest what kernel modules to use
lxd_profile_create__02_kernel_modules() {
    local modules=(ip_tables ip6_tables netlink_diag nf_nat overlay)
    lsmod | grep -F -q xt_conntrack && modules+=(xt_conntrack)

    join "," "${modules[@]}"
    #shellcheck disable=SC2154
    lxc profile set "$LXD_REMOTE$LXD_PROFILE_NAME" linux.kernel_modules "$join_ret"

    # we need to have these modules loaded in host for this to work
    info "checking for modules to load on host ..."
    local d=/etc/modules-load.d
    local f
    if [ -d "$d" ]; then
        f="$d/k8s.conf"
    fi
    for m in "${modules[@]}"; do
        if ! lsmod | grep -qE "^$m\s+" ; then
            sudo -i modprobe "$m"
        fi
        if [ -n "$f" ] && ! grep -qE "^$m\$" "$f" 2>/dev/null; then
            echo "$m" | sudo tee -a "$f"
        fi
    done
}


# This is NOT a secure setup
# But since it is intended for development...
#
lxd_profile_create__04_security() {
    # lxc.seccomp.profile - required at least for allowing us to have a nfs-server-provisioner working inside
    #      but please note that security is drastically? reduced
    #
    
    rawLXC=$(cat <<-EOS
lxc.apparmor.profile=unconfined
lxc.cap.drop=
lxc.cgroup.devices.allow=a
lxc.mount.auto=proc:rw sys:rw cgroup:rw
lxc.seccomp.profile=
EOS
)

    lxc profile set "$LXD_REMOTE$LXD_PROFILE_NAME" raw.lxc "$rawLXC"
    lxc profile set "$LXD_REMOTE$LXD_PROFILE_NAME" security.privileged "true"
    lxc profile set "$LXD_REMOTE$LXD_PROFILE_NAME" security.nesting "true"

    lxc profile device add "$LXD_REMOTE$LXD_PROFILE_NAME" aadisable1 disk path=/sys/module/apparmor/parameters/enabled source=/dev/null

}


lxd_profile_create__06_networking() {
    # and add the eth0 device as well (we can't use the 'default' profile in the same time')

    lxc profile device add "$LXD_REMOTE$LXD_PROFILE_NAME" eth0 nic name=eth0 nictype=bridged parent=lxdbr0
    
    lxc profile device add "$LXD_REMOTE$LXD_PROFILE_NAME" aadisable disk path=/sys/module/nf_conntrack/parameters/hashsize source=/dev/null

}

lxd_profile_create__05_storage() {
    # Ensure we're using a 'dir' based storage'
    local storage_pool
    storage_pool=$(lxdGetStoragePoolDirType)
    lxc profile device add "$LXD_REMOTE$LXD_PROFILE_NAME" root disk path=/ pool="$storage_pool"
}

lxd_profile_create__07_host_root_disk() {
    # add host root disk. Else, sometimes kubelet fails to get info on its root directory    
    local storage_pool
    storage_pool=$(lxdGetStoragePoolDirType)
    local storage_path
    storage_path=$(lxdGetStoragePoolPath "$storage_pool")


    mountInfo=$(storage_dir_mount_info "$storage_path")
    test -n "$mountInfo" || bail "Failed to get mount info for storage directory $storage_path"
    mountDevice=$(echo "$mountInfo" | cut -f 1 -d ' ')
    nameMountDevice=${mountDevice//[\/]/_}
    test -b "$mountDevice" || bail "Mount point $mountDevice for storage directory $storage_path is not a block device?"
    lxc profile device add "$LXD_REMOTE$LXD_PROFILE_NAME" "$nameMountDevice" unix-block path="$mountDevice" source="$mountDevice"
}


lxd_profile_create__07_kernel_messages() {
    if [ -e /dev/kmsg ]; then
	    lxc profile device add "$LXD_REMOTE$LXD_PROFILE_NAME" dev_kmsg unix-char path=/dev/kmsg source=/dev/kmsg
    elif  [ -e /dev/console ]; then
	    lxc profile device add "$LXD_REMOTE$LXD_PROFILE_NAME" dev_kmsg unix-char path=/dev/kmsg source=/dev/console
    fi
}


lxdGetProfileVersion() {
    if lxc query "$LXD_REMOTE/1.0/profiles/$LXD_PROFILE_NAME" >/dev/null 2>/dev/null; then
        lxc profile get "$LXD_REMOTE$LXD_PROFILE_NAME" "$VERSION_FIELD"
    fi
}

lxdCheckProfileVersion() {
    local v=
    v=$(lxdGetProfileVersion)
    if [ -z "$v" ]; then        
        bail "No profile set. You need to run setup (--setup)"
    fi

    if [ "$v" != "$VERSION" ]; then
        warn "profile $LXD_PROFILE_NAME is of different version then what the script can create"
        warn "you might want to run the setup again (--setup)"
    fi
}


lxdCreateProfile() {
    local v
    v=$(lxdGetProfileVersion)

    local useTemporaryProfile=""

    if [ -n "$v" ]; then
        if [ "$v"  != "$VERSION" ]; then
            warn "profile $LXD_PROFILE_NAME is of different version ($v). Will recreate, version '$VERSION'"
            local c
            c=$(lxdProfileUsageCount "$LXD_PROFILE_NAME")
            if [ "$c" != "0" ]; then
                useTemporaryProfile=1
            else
                lxc profile delete "$LXD_PROFILE_NAME"
            fi
        else
            warn "profile $LXD_PROFILE_NAME already exists. Leaving as is..."
            return 0
        fi
    fi

    local origLxdProfileName="$LXD_PROFILE_NAME"
    if [ -n "$useTemporaryProfile" ]; then
        LXD_PROFILE_NAME="${LXD_PROFILE_NAME}-$VERSION"
    fi
    info "creating profile '$LXD_PROFILE_NAME'"
    runFunctions '^lxd_profile_create__'
    info "profile '$LXD_PROFILE_NAME' created"

    if [ -n "$useTemporaryProfile" ]; then
        lxc profile show "$LXD_REMOTE$LXD_PROFILE_NAME" | lxc profile edit "$LXD_REMOTE$origLxdProfileName"
        lxc profile delete "$LXD_REMOTE$LXD_PROFILE_NAME"
        LXD_PROFILE_NAME="$origLxdProfileName"
    fi
}
