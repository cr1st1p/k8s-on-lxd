# shellcheck shell=bash

info() {
    echo "INFO: " "$@"
}

warn() {
    echo "WARN: " "$@"
}


err() {
    echo "ERR:  " "$@"
}

bail() {
    err "$@"
    exit 1
}

isFunction() {
    declare -f "$1" > /dev/null
}

commandExists() {    
	command -v "$1" &>/dev/null
}


checkForCommand() {
    local prog="$1"

    if ! commandExists "$1" ; then
        err "Program '$prog' not found. We need it to continue."
        err "Install it by yourself, or you can run 'sudo test/setup-pre-req.sh'"
        err "to the install the minimal dependencies"
        exit 1
    fi
}


# result is in global variable join_ret - as to not run another shell
#
join() {
    # $1 is sep
    # $2... are the elements to join
    # return is in global variable join_ret
    local sep=$1 IFS=
    join_ret=$2
    shift 2 || shift $(($#))
    join_ret+="${*/#/$sep}"
}


# list defined function names, matching specified regexp pattern 
listFunctions() {
        pattern="$1"
    
    	set | grep -P '^\S+\s*\(\)' | cut -d ' ' -f 1 | grep -P "$pattern" | sort
}


runFunctions() {
        pattern="$1"
        shift
        
        for f in $(listFunctions "$pattern") ; do
                isFunction "$f" || continue
                $f "$@"
        done
}

# returns the info about the mount point (as given by 'mount') for the specified directory or one of
# its ancestor if it is not itself a mount directory (ending in '/')
#  
storage_dir_mount_info() {
    d=$1 # directory we're interested in
        
    while true ; do
        mountLine=$(mount | grep -P "$d +type")
        if [ -n "$mountLine" ]; then
            echo "$mountLine"
            return 0
        fi
        
        if [ "$d" = "/" ]; then
            echo ""
            return 0
        fi
        d=$(dirname "$d")
        continue
    done
}


makeValidHostname() {
    echo "$1" | sed -Ee 's@[\.]@-@gi'
}

elementIn () {
  local e 
  local match="$1"
  shift
  for e in "$@"; do 
    [[ "$e" == "$match" ]] && return 0
  done
  return 1
}

kernelModuleLoaded() {
    local m="$1"
    lsmod | grep -qE "^$m\s+"
}

kernelModuleLoad() {
    local m="$1"

    if ! kernelModuleLoaded "$m"; then
        info "Need to load kernel module '$m', via 'sudo' call."
        sudo -i modprobe "$m"
    fi
}


# functions to compare software versions in dot format
#
verlte() {
        printf '%s\n%s' "$1" "$2" | sort -C -V  
}

verlt() {
    ! verlte "$2" "$1"
}

# Keep it in sync with code from lxd.sh, in lxdGetIp
# return the name of the default interface. based on the default route
getNetDevice() {
    if commandExists netstat; then
        netstat -rn | grep '^0.0.0.0' | gawk '{print $NF}' | head -1
    elif commandExists ip; then
        ip route list | grep -P '^default.*dev' | sed -E -e 's/.*dev (\S+).*/\1/'|uniq
    else
        bail "Don't have programs to find default network interface ('netstat' or 'ip')"
    fi
}

# get the IPv4 address of the network device given as parameter
getIpOfNetDevice() { 
    ip -o -4 addr list "$1" | gawk '{print $4}' | cut -d/ -f1 | head -1
}


getRandomLocalPort() {
    local LOWERPORT UPPERPORT  PORT
    read -r LOWERPORT UPPERPORT < /proc/sys/net/ipv4/ip_local_port_range
    
    while true; do
        PORT=$(shuf -i "$LOWERPORT-$UPPERPORT" -n 1)
        ss -lpn | grep -q ":$PORT " || break
    done
    echo "$PORT"
}


ensureClusterNameIsSet() {
    if [ -z "$CLUSTER_NAME" ]; then
        bail "Need to give me the name prefix to use, via -n NAME"
    fi
}
