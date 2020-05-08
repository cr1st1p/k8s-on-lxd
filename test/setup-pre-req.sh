#! /bin/bash

# for the moment, too many quirks to use saltstack - i.e. it would just do cmd.run ...
# This script's role: ensure you're having the minimal things insalled on your
# development box/testing VM:
# lxc, kubectl, pwgen
#
# Helpful: you can play with iptables to see if system is working with the proxy:
# l=$(ip route | grep default)
# sudo ip route del
# sudo ip route add ${l/default/10.0.0.0/8}


set -e
#set -x # DEBUG:


SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#shellcheck source=lib/general.sh
source "$SCRIPT_PATH/../lib/general.sh"
#shellcheck source=lib/os-detect.sh
source "$SCRIPT_PATH/../lib/os-detect.sh"
#shellcheck source=lib/apt.sh
source "$SCRIPT_PATH/../lib/apt.sh"

tempUser=vagrant
tempGroup=$tempUser


proxy_in_use() {
    #shellcheck disable=SC2154,SC2153
    test -n "${http_proxy}${https_proxy}${HTTP_PROXY}${HTTPS_PROXY}"
}


create_proxy_files() {
    if proxy_in_use; then
        info "Proxy setup detected, creating appropriate files"

        local f=/etc/profile.d/00-proxy.sh

        cat > "$f" << EOS
# Main  settings for http proxy variables
# MANDATORY: keep them in a=b format
EOS

        local crtIP
        crtIP=$(getIpOfNetDevice "$(getNetDevice)")

        for name in http_proxy https_proxy no_proxy; do
            local value=${!name}
            if [ -n "$value" ]; then
                if [ "$name" = "no_proxy" ]; then
                    # lets ensure a few things are in there.
                    # note that not all programs know to use CIDRs from it
                    for v in "127.0.0.1" "localhost" "*.lxd" "10.0.0.0/24", "172.0.0.0/8" "$crtIP"; do
                        [[ "$value" = *"$v"* ]] || value="$value,$v"
                    done
                fi
                echo "$name=\"$value\"" >> "$f"
            fi
        done

        local f=/etc/profile.d/01-proxy.sh

        test ! -f "$f" || rm "$f"

        for name in http_proxy https_proxy no_proxy; do
            echo "[ -z \"\$$name\" ] || export $name" >> "$f"
        done

    fi
}



# ===============

update_software_db() {
    info "Updating software database"
    if is_debian_like; then
        apt_update
    elif is_arch_like; then
        arch_update
    else
        err "Do not know how to update packages list"
    fi
}


# like in the proxy-cache addon:
setServiceProxyEnvironment() {
    local serviceName="$1"

    info "creating systemd file for service '$serviceName'"

    local d="/etc/systemd/system/$serviceName.service.d/"
    local fd="$d/http-proxy.conf"

    [ -d "$d" ] || mkdir -p "$d"
    cat > "$fd" <<EOS
[Service]    
EnvironmentFile=-/etc/profile.d/00-proxy.sh
EOS

    systemctl daemon-reload
    # it does not also a restart of service, since service might be stoped (like docker)
}



# ----------
arch_install() {
    pacman -S --needed --noconfirm "$@"
}

arch_update() {
    # TODO: check if not updated recently
    pacman -Sy
}


arch_prepare_for_aur_installs() {
    	commandExists gcc && commandExists git && return 0
    	
    	info "ARCH: adding packages to be able to install from AUR"
        arch_install archlinux-keyring
        # as individual step, else we're going to get more updated than we'd want :
    	arch_install systemd-libs libidn2 systemd iptables pacman 

    	#exit -1
	#echo -e 'y\n' | pacman -S --needed systemd-libs systemd libidn2 iptables
	# Grr.
	# https://forum.manjaro.org/t/manjaro-stuck-on-boot-screen-libidn2-so-4-missing/72999/41
	if ldd "$(command -v pacman)" | grep -F -q libidn2.so.4; then
	    	if [ ! -f /usr/lib/libidn2.so.4 ]; then
	    	    src="$(find /usr/lib/ -maxdepth 1 -name 'libidn2.so.*' 2>/dev/null | tail -n 1)"
	    	    ln -s "$src" /usr/lib/libidn2.so.4
		fi
	fi
	arch_install glibc base-devel libutil-linux
	arch_install git
}

arch_install_aur_package() {
    	pkg=$1
    	dirName="$pkg"
    	url="https://aur.archlinux.org/$pkg.git"
    	scriptInput=$2
    	
        arch_prepare_for_aur_installs
        info "Will install package '$pkg' from AUR repo. Can take a while"
        
        # /tmp/ might be a tmpfs with limited space. 'kubernetes-bin' needs at least 1.5G
        pushd /var/tmp/ &>/dev/null
        if [ -d "$dirName" ]; then
            pushd "$dirName" &>/dev/null
            git pull
    	else
		    info "Will git clone $pkg"    	    
        	git clone "$url"
        	pushd "$dirName" &>/dev/null
    	fi
        chown -R $tempUser:$tempGroup .
        info "Will make package for $pkg"
        if [ -n "$scriptInput" ]; then
        	echo -e "$scriptInput" | su "$tempUser" -c 'makepkg -si --noprogressbar'
    	else
            su "$tempUser" -c 'makepkg -si --noconfirm --noprogressbar'
    	fi
    	info "  done"
        popd &>/dev/null
        popd &>/dev/null
}


snapd_setup() {
    snapd_path_setup
    snapd_proxy_use
}


snapd_path_setup() {
        # we need some env vars for programs to be found
        for f in snapd.sh apps-bin-path.sh; do
            # || true -> don't exit script if we don't source the file
            if [[ ! $PATH =~ "snap" && -f "/etc/profile.d/$f" ]]; then
                #shellcheck disable=SC1090
                source "/etc/profile.d/$f"
            fi
        done
}

snapd_proxy_use() {
    # https://bugs.launchpad.net/ubuntu/+source/snapd/+bug/1579652
    proxy_in_use || return 0

    commandExists snap || return 0

    info "Proxy detected, will set snapd to use your proxy"
    local https_proxy=${https_proxy:-$http_proxy}


    setServiceProxyEnvironment "snapd"
    systemctl restart snapd.service
}


snapd_post_install() {
        snapd_proxy_use
        snapd_wait_after_install
}

snapd_wait_after_install() {
        # we get some strange error like 'too early for operation, device not yet seeded...'
        snap wait system seed.loaded 
        sleep 10
}


arch_install_snapd() {
        arch_install_aur_package snapd
        snapd_setup

        # https://forum.snapcraft.io/t/cant-install-or-refresh-snaps-on-arch-linux/8690/34
        systemctl enable --now snapd.socket
        ln -s /var/lib/snapd/snap /snap
        systemctl start --now snapd
}
# -------------

install_pwgen_program() {    
    commandExists pwgen && return 0
    
    info "Installing 'pwgen' program"
    
    if is_debian_like; then
        apt_install pwgen
    elif is_arch_like; then
    	arch_install pwgen
    else
        bail "Want to install 'pwgen' program but don't know how"
    fi 
}

install_jq_program() {    
    commandExists jq && return 0
    
    info "Installing 'jq' program"
    
    if is_debian_like; then
        apt_install jq
    elif is_arch_like; then
    	arch_install jq
    else
        bail "Want to install 'pwgen' program but don't know how"
    fi 
}


install_netstat_program() {
    commandExists netstat && return 0
    
    info "Installing 'netstat' program"
    
    if is_debian_like; then
        apt_install net-tools
    elif is_arch_like; then
    	arch_install net-tools
    else
        bail "Want to install 'netstat' program but don't know how"
    fi 
}


install_snap_program() {
    snapd_path_setup
    commandExists snap && return 0
    	
    info "Installing 'snapd'"

    if is_arch_like; then
        arch_install_snapd
    elif is_ubuntu ; then
        apt_install snapd
    else
        bail "Don't know how to install 'snapd'"
    fi

    snapd_post_install    
}


install_sysctl_program() {
    commandExists sysctl && return 0

    info "Installing 'sysctl' program"

    if is_debian_like; then
        apt_install procps
    elif is_arch_like; then
        arch_install procps-ng    
    else
        bail "Don't know how to install 'sysctl' program"
    fi
}


lxd_proxy_setup() {
    local serviceName
    serviceName=$(systemctl | grep -E 'lxd.*service' | sed -Ee 's@\s*(.*?)\.service.*@\1@' | grep -v 'lxd-containers')
    test -n "$serviceName"

    info "Setting proxy info inside LXD"

    setServiceProxyEnvironment "$serviceName"
    systemctl restart "$serviceName"

    # if [ -n "$http_proxy" ]; then
    #     lxc config set core.proxy_http "$http_proxy"
    # fi

    # if [ -n "$https_proxy" ]; then
    #     lxc config set core.proxy_https "$https_proxy"
    # fi
}


lxd_install() {
    commandExists lxd && return 0
    
    if is_arch_like ; then
        if false ; then
            info "Installing LXC and LXD from AUR"
        	pacman -S --noconfirm lxc
        	arch_install_aur_package sqlite-replication "y\nY\n"
        	
        	arch_install_aur_package lxd
        	systemctl enable lxd.service
        	systemctl start lxd.service        	
        else    	
            arch_install_snapd
            info "Installing 'lxd' from snap"
            snap install --color=never --unicode=never lxd
        fi        
    else
        if is_ubuntu; then
            info "Installing 'lxd' from snap"            
            snap install --color=never --unicode=never lxd            
        else
            bail "TODO: need to install LXD but do not know how"
        fi
    fi

}


lxd_init() {
    info "Checking to see if we need to 'lxd init'"
    if ! ip link show lxdbr0 &>/dev/null ; then
    	lxd init --auto || bail "Failed to 'lxd init'"
    fi	
}

lxd_user_group() {
    info "checking to see if you have permissions to run 'lxc'"
    if su -l -c 'lxc list' $tempUser 2>&1 | grep -F -q 'permission denied' ; then
    	usermod -G lxd -a "$tempUser"
    fi
}

# ---------
install_kubectl() {
    commandExists kubectl && return 0

    info "Installing 'kubectl'"

    if is_ubuntu; then
    	snap install --color=never --unicode=never --classic kubectl
    elif is_arch_like; then

    	# TODO: install specific version
        arch_install_aur_package kubectl-bin    	
    else
        bail "Want to install 'kubectl' but do not know how"
    fi
    
    if ! commandExists kubectl; then
        bail "Failed to install 'kubectl'"
    fi 
}



# --------------
info "Starting to do the minimal setup for your machine - lxc, pwgen, kubectl, jq"
if [ "0" != "$(id -u)" ]; then
    bail "You need to run this script as 'root'"
fi

create_proxy_files

update_software_db
snapd_setup

install_pwgen_program
install_netstat_program
install_snap_program
install_sysctl_program
install_jq_program

lxd_install
lxd_init
lxd_user_group
lxd_proxy_setup

install_kubectl

info "Disabling swap"
swapoff -a
info "== done with setup pre-req =="

