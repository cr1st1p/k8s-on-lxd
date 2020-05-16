# shellcheck shell=bash

__wrote_about_missing_programs=0
write_about_missing_programs() {
    [ "$__wrote_about_missing_programs" = "0" ] || return 0
    __wrote_about_missing_programs=1

    err "You are missing some of the required programs to run"
    cat <<EOS

You have 2 choices:
1 - just run our setup script and it will hopefully install all of them:
    sudo ${SCRIPT_PATH}/test/setup-pre-req.sh
2 - Install them by yourself. Short information on how to intall each of them will follow.


EOS

    write_about_arch_packages_failure
}


__wrote_about_missing_snapd=0
write_about_snapd_install() {
    commandExists snap && return 0
    [ "$__wrote_about_missing_snapd" = "0" ] || return 0
    __wrote_about_missing_snapd=1

    if is_ubuntu; then
        cat <<'EOS'
You need to install first 'snapd'. Follow the documentation at 
    https://snapcraft.io/docs/installing-snap-on-ubuntu
    Usually this would entail:
    sudo apt update
    sudo apt install snapd
EOS
    elif is_arch_like; then
        cat <<'EOS'
You need to install first 'snapd'. Follow the documentation at 
    https://snapcraft.io/install/snapd/arch
EOS
    else 
        cat <<'EOS'
You need to install first 'snapd'. Follow the documentation at 
    https://snapcraft.io/docs/installing-snapd
EOS
    fi
}

__wrote_about_arch_packages_failure=0
write_about_arch_packages_failure() {
    is_arch_like || return 0
    
    [ "$__wrote_about_arch_packages_failure" = "0" ] || return 0
    __wrote_about_arch_packages_failure=1
    # Examples:
    # today, 'make', used to build 'snapd' is using libffi.so.6, but libffi.so is at version libffi.so.7!
    warn "On Arch based Linux distros, sometimes packages are broken, so the following setup commands *can* fail."
}

host_check_lxd_installed() {
    if commandExists lxd; then
        local v
        v=$(lxd --version)
        if [[ "$v" =~ "3."* ]]; then
            warn "I think you have an older LXD version ($v). Try installing LXD as a snapd package"
        fi
        return 0
    fi

    write_about_missing_programs

    err "Missing program 'lxd'"

    if is_ubuntu || is_arch_like;  then
        write_about_snapd_install
        cat <<'EOS'
Install LXD as a snap package (usually it is the newest version):
    sudo snap install --color=never --unicode=never lxd
EOS
    else
        cat <<'EOS'
Sorry, not sure how to install LXD on your OS. Usually you should install it via snapd.
Get 'snapd' installed by following https://snapcraft.io/docs/installing-snapd, and then:
    sudo snap install --color=never --unicode=never lxd
EOS
    fi

    cat << 'EOS'
After install, do not forget to initialize LXD by running
    sudo lxd init
EOS
}

host_check_lxc_installed() {
    if commandExists lxc; then
        local v
        v=$(lxc --version)
        if [[ "$v" =~ "3."* ]]; then
            warn "I think you have an older LXD *client* version ($v). Try installing LXD as a snapd package to use both a new(er) server and client"
            if is_debian_like; then
                local pkg
                pkg=$(dpkg-query -S "$(which lxc)" 2>/dev/null | cut -d ':' -f 1)
                [ -n "$pkg" ] && echo -e "  You probably also have to remove package $pkg:\n\tsudo apt remove $pkg"

            fi
        fi
        return 0
    fi
    ! commandExists lxd || err "Strange - you have LXD but no LXD client - program 'lxc' !? Kindly please report your "
}


host_check_kubectl_installed() {
    commandExists kubectl && return 0

    write_about_missing_programs

    err "Missing program 'kubectl'"

    if is_ubuntu || is_arch_like; then
        write_about_snapd_install
        cat <<'EOS'
  Install kubectl as a snap package (usually it is the newest version):
    sudo snap install --color=never --unicode=never --classic kubectl
EOS
    else
        cat <<'EOS'
  Sorry, not sure how to install kubectl on your OS. Please report, so that we can improve the suggestion in here.
EOS
    fi
}


lxd_check_init_was_run() {
    local has_net_device
    has_net_device=$(lxc query /1.0/networks/lxdbr0 2>/dev/null | jq -r '.managed')
    local count
    count=$(lxc query /1.0/storage-pools | jq '. | length')
    
    if [ "$has_net_device" != "true" ] || [ "$count" = "0" ]; then
        err "I can not find lxdbr0 device or there are no LXD storage pools defined."
        err "Are you sure you launched 'sudo lxd init' ?"
        exit 1
    fi
}


host_check_minimum_requirements() {
    host_check_lxd_installed
    host_check_lxc_installed

    local missing=""
    local packages=()
    declare -A progs
    local package_install_cmd=""

    if is_debian_like; then
        progs=( ["pwgen"]="pwgen" ["netstat"]="net-tools" ["ip"]="iproute2" \
            ["gawk"]="gawk" ["grep"]="grep" ["sysctl"]="procps" ["sort"]="coreutils" \
            ["jq"]="jq" ["shuf"]="coreutils")

        package_install_cmd="apt-get install -qq -y --no-install-recommends --no-install-suggests"
    elif is_arch_like; then
        progs=( ["pwgen"]="pwgen" ["netstat"]="net-tools" ["ip"]="iproute2" \
            ["gawk"]="gawk" ["grep"]="grep" ["sysctl"]="procps-ng" ["sort"]="coreutils" \
            ["jq"]="jq" ["shuf"]="coreutils")

        package_install_cmd="pacman -S --needed --noconfirm"
    else
        progs=( ["pwgen"]="?" ["netstat"]="?" ["ip"]="?" \
            ["gawk"]="?" ["grep"]="?" ["sysctl"]="?" ["sort"]="?" \
            ["jq"]="?" ["shuf"]="?")
    fi
    for prog in "${!progs[@]}"; do
        if ! commandExists "$prog"; then
            [ -z "$missing" ] || missing="$missing, "
            missing="$missing$prog"
            packages+=("${progs[$prog]}")
        fi
    done
    if [ -n "$missing" ]; then
        write_about_missing_programs
        

        err "Missing programs: ${missing}."
        if [ -n "$package_install_cmd" ]; then
            echo "  To install, run:"
            echo "  sudo $package_install_cmd ${packages[*]}"
        fi
        
    fi

    host_check_kubectl_installed

    # TODO: check for minimum versions for some of these programs
    # TODO: check 'sort' does correctly support the -V param

    [ "$__wrote_about_missing_programs" = "0" ] || exit 1

    lxd_check_init_was_run
    warn_about_swap
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

