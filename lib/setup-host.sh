# shellcheck shell=bash

host_check_minimum_requirements() {
    for n in lxc pwgen kubectl netstat ip gawk netstat grep sysctl sort jq shuf; do
        checkForCommand "$n"
    done
    # TODO: check for minimum versions for some of these programs
    # TODO: check 'sort' does correctly support the -V param
}



setup_host__01_conntrack_kernel_module() {
    maybe_install_module /sys/module/nf_conntrack/parameters/hashsize nf_conntrack
}

setup_host__02_conntrack_hashsize() {
    info "checking nf_conntrack hashsize, via 'sudo' call"
    local f=/sys/module/nf_conntrack/parameters/hashsize
    declare -i crt
    crt=$(sudo head "$f")
    if [[ $crt -lt 65536 ]]; then
      info "  too low. Need to update it."
      sudo bash -c "echo 65536 > '$f'"
    fi
}



# https://bbs.archlinux.org/viewtopic.php?id=237993
# https://bbs.archlinux.org/viewtopic.php?id=240427
disable_dnssec() {
    local cfg=/etc/systemd/resolved.conf
    
    if [ ! -f "$cfg" ] || grep -q -P "^DNSSEC\s*=\s*no" $cfg; then
        return 0
    fi
    warn "Will disable DNSSEC. Having trouble [on my box], sometimes, to resolve api.snapcraft.io"
    sudo bash -c "echo 'DNSSEC=no' >> '$cfg'"
    sudo -i systemctl restart systemd-resolved
    
}

setup_host__02_disable_dnssec() {
    disable_dnssec
}

maybe_install_module() {
    local sysFile="$1"
    local module="$2"

    if [ ! -f "$sysFile" ]; then
        kernelModuleLoad "$module"
    	if [ ! -f "$sysFile" ]; then
    	    bail "Failed to make $sysFile appear in the system" 
    	fi
    fi	
}


setup_host__03_sys_file_bridge_iptables() {
    maybe_install_module /proc/sys/net/bridge/bridge-nf-call-iptables br_netfilter
}

