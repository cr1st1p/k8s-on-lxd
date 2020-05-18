# shellcheck shell=bash

#
# Various functions to work with LXD daemon
# yes, prefix is either lxd or lxc...
#


lxdContainerExists() {
    local container=$1

    lxc query "/1.0/containers/$container"  > /dev/null 2>/dev/null
}


lxdStatus() {
    local container=$1

    lxc query "/1.0/containers/$container" 2> /dev/null | jq -r '.status'
}

lxdSetFixedIp() {
    local container="$1"
    local ip="$2"
    local intf="$3"

    [ -n "$intf" ] || intf=$(lxdGetHostInterface)

    info "Setting container '$container' to have fixed IP $ip"

    lxc network attach "$intf" "$container" eth0 eth0
    lxc config device set "$container" eth0 ipv4.address "$ip"
}


lxdGetConfiguredIp() {
    local container="$1"

    lxc query "/1.0/containers/$container" 2>/dev/null | jq -r '.devices.eth0["ipv4.address"]' | grep -Ev '^null$' || true
}


# runtime IP
lxdGetIp() {
    local container=$1
    
    # count of ip addresses
    local n
    n=$(lxc query "/1.0/containers/$container/state" | jq -r '[.network|to_entries[] | .value.addresses[] + { name: .key} | select(.family=="inet" and .name != "lo")| .address] | length' 2>/dev/null)
    if [ -z "$n" ] || [ "0" = "$n" ]; then
        return 0
    fi

    # we'll run code inside the container to get the IP, based on our getIpOfNetDevice() implementation
    lxcExecBashCommands "$container" <<EOS
err() {
    echo "ERR:  " "\$@"
}

bail() {
    err "\$@"
    exit 1
}

commandExists() {    
	command -v "\$1" &>/dev/null
}

getNetDevice() {
    if commandExists netstat; then
        netstat -rn | grep '^0.0.0.0' | gawk '{print \$NF}' | head -1
    elif commandExists ip; then
        ip route list | grep -P '^default.*dev' | sed -E -e 's/.*dev (\S+).*/\1/'|uniq
    else
        bail "Don't have programs to find default network interface ('netstat' or 'ip')"
    fi
}

# get the IPv4 address of the network device given as parameter
getIpOfNetDevice() { 
    ip -o -4 addr list "\$1" | gawk '{print \$4}' | cut -d/ -f1 | head -1
}

d=\$(getNetDevice)
if [ -n "\$d" ]; then
    getIpOfNetDevice "\$d"
fi
EOS
}


lxdWaitIp() {
    local container=$1

    # Do NOT use 'SECONDS', that is bash predefined
    N_SECONDS=3
    while true ; do
        ip=$(lxdGetIp "$container")
        test -z "$ip" || break
        echo -n "${EMOTICON_WAITING}Sleeping $N_SECONDS seconds to have the container get its IP..."
        sleep $N_SECONDS
        echo
    done
}


lxcExecDirect() {
    local container=$1
    cmd=$2
    shift
    shift
    
    lxc exec -Tn "$container" "$cmd" -- "$@"
}


lxcExec() {
    local container=$1
    local cmd=$2
    shift
    shift
    
    [ -n "$DEBUG" ] && debugParam="-x"

    # we actually want to go through shell, to have all the environment variables set
    #echo $cmd "'$@'" | lxcExecBashCommands "$container"
    lxc exec -Tn "$container" bash -- $debugParam -le -c "$cmd \"\$@\"" "$cmd" "$@"
}


lxcExecBash() {
    local container=$1
    shift
    
    [ -n "$DEBUG" ] && debugParam="-x"
    lxc exec -Tn "$container" bash -- $debugParam -le -c "$@"
}


lxcExecBashWithStdin() {
    local container=$1
    shift
    
    [ -n "$DEBUG" ] && debugParam="-x"
    lxc exec -T "$container" bash -- $debugParam -le -c "$@"
}


lxcExecBashCommands() {
    local container=$1
    shift
    
    [ -n "$DEBUG" ] && debugParam="-x"

    lxc exec -T "$container" bash -- $debugParam -le -s 
}


lxcCheckContainerIsRunning() {
    container=$1
    
    if ! lxdContainerExists "$container" ; then
    	bail "Container '$container' should be created first"
    fi
    
    containerStatus=$(lxdStatus "$container" 2>/dev/null)
    if [ "$containerStatus" != "Running" ]; then
        bail "Container with master node $container should be running"
    fi
    lxdWaitIp "$container"
}


ensureLxdIsInstalled() {
    checkForCommand lxc
    
    # check for permissions as well
    if lxc list 2>&1 | grep -F 'permission denied' ; then
    	bail "LXD: seems to have problems with permissions. Please fix (maybe not part of the correct group?)"
    fi 
}

lxcCheckImageExists() {
    local image_name=$1
    
    lxc query "/1.0/images/aliases/$image_name" >/dev/null 2>/dev/null
}



ensureLxdImageExists() {
    local image_name=$1
    
    ensureLxdIsInstalled
    if ! lxcCheckImageExists "$image_name" ; then
        bail "Image '$image_name' does not exist. Please build it first" 
    fi
}

lxdProfileExists() {
    local name="$1"
    lxc query "/1.0/profiles/$name" >/dev/null 2>/dev/null
}

lxdProfileUsageCount() {
    lxc query "/1.0/profiles/$1" | jq -r '.used_by | length'
}

lxdContainersUsedByProfile() {
    local profileName="$1"
    lxc query "/1.0/profiles/$profileName" | jq -r '.used_by | .[] | ltrimstr("/1.0/containers/")'
}


lxdGetHostInterface() {
    # alternative: query for the networks and see which one is 'managed=true'
    # with lxc query "/1.0/networks"
    #lxc query /1.0/profiles/default | jq -r '.devices[].parent' | grep -q 'lxdbr0' || bail "Strange - we expected your LXD bridge to be lxdbr0"
    local dumb
    dumb=$(lxc query /1.0/networks/lxdbr0 2>/dev/null | jq -r '.managed')
    if [ "$dumb" != 'true' ]; then
        bail "Strange - we expected your LXD bridge to be lxdbr0"
    fi
    echo -n 'lxdbr0'
}

lxdGetHostIpCidr() {
    local device
    device=$(lxdGetHostInterface)
    ip addr show "$device" | grep -F 'inet ' | sed -E -e 's@ *inet +([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+).*@\1@'
}

lxdGetHostIp()
{
    local device
    device=$(lxdGetHostInterface)
    ip addr show "$device" | grep -F 'inet ' | sed -E -e 's/ *inet +([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/).*/\1/'
}

lxcListAll() {
    lxc query /1.0/containers | jq -r '.[] | ltrimstr("/1.0/containers/")'
}

lxcListByPrefixAll()  {
    local prefix="$1"
    lxcListAll | grep -P "^$prefix-(master|worker-\d+)\$"
}

lxcListByPrefixAllWorkers()  {
    local prefix="$1"
    lxcListAll | grep -P "^$prefix-worker-\d+\$"
}

lxcListByPrefixRunning() {
    local prefix="$1"
    for n in $(lxcListByPrefixAll "$prefix") ; do
        local s
        s=$(lxdStatus "$n")
        [ "$s" == "Running" ] && echo "$n"
    done
}

lxcListByPrefixStopped() {
    local prefix="$1"
    for n in $(lxcListByPrefixAll "$prefix") ; do
        local s
        s=$(lxdStatus "$n")
        [ "$s" == "Stopped" ] && echo "$n"
    done
}


lxdGetStoragePoolDirType() {
    for url in $(lxc query /1.0/storage-pools | jq -r '.[]'); do
        local type
        type=$(lxc query "$url" | jq -r '.driver')
        if [ "dir" = "$type" ]; then
            # print the name
            lxc query "$url" | jq -r '.name'
        fi
    done
}

lxdGetStoragePoolPath() {
    local name="$1"
    lxc query "/1.0/storage-pools/$name" 2>/dev/null | jq -r '.config.source'
}



