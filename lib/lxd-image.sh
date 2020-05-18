# shellcheck shell=bash

# function to create a kubernetes master and worker images
# It will use ubuntu:18.04 as base image
#
# needs:
# - general.sh loaded
# - lxd.sh loaded
# - var $LXD_PROFILE_NAME
#
# 

APT_REMOVE=(apt purge -y)

use_snap=1



lxcChangeVarInFile() {
    local container=$1
    f=$2
    var=$3
    key=$4
    value=$5

    # DO NOT forget to backquote $
    lxcExecBashCommands "$container" <<EOS
    
    # ensure file exists
    test -f $f || touch $f
    
    # ensure we're having the value quoted
    sed -ie "s/${var}=\\\$/${var}=\"\"/" ${f}

    if grep -q -P -- "${var}=.*--${key}=" $f ; then
        sed -Eie "s/(--${key}=)[^\"]*/\1${value}/" $f
    else
        sed -Eie "s/(.*${var}=\"[^\"]*)/\1 --${key}=${value}/" $f
    fi

EOS

    #lxc exec $container cat $f
}


prepareLxdImageStartContainer() {
    local sourceImage=$1
    local container=$2
    
    if lxdContainerExists "$container" ; then
        warn "LXD Container $container exists. Will *continue* to build image within it"
        status=$(lxdStatus "$container")
        if [ "$status" = "Stopped" ]; then
            info "Starting stopped container $container"
            lxc start "$container"
        fi
    else
        # we should also be using a privileged container even when building it
        # Not sure who the f. sends something on stdin, inside vagrant. https://github.com/lxc/lxd/issues/6228
        lxc launch -p "$LXD_PROFILE_NAME" "$sourceImage" "$container" < /dev/null
    fi
    
    lxdWaitIp "$container"
}


run_script_inside_container() {
    local container="$1"
    shift

    local d
    # wait for systemd to cleanup /tmp/, else it will remove our temp dir
    # SEEME: some other way
    sleep 5s 

    d=$(lxcExecDirect "$container" mktemp -d)

    info "Copying script files to container"

    lxc file push "$SCRIPT_PATH/k8s-on-lxd.sh" "${container}$d/"
    lxc file push -r "$SCRIPT_PATH/lib" "${container}$d/"
    lxc file push -r "$SCRIPT_PATH/addons" "${container}$d/"

    lxcExecBash "$container" "$d/k8s-on-lxd.sh  --k8s-version '$K8S_VERSION' $*"

    # and remove them
    lxcExec "$container" rm -rf "$d"
}



# =============================
# prepareLxdImage__* functions are called to create and launch the base LXD image
# later one, it copies our own code into the container and runs a different list of 
# steps (insideLxdImaage__* - see after this section)
# 
prepareLxdImage__01_start_container() {
    ubuntu_version=18.04

    ubuntu_image_local="ubuntu-$ubuntu_version"
    
    info "Checking for local ubuntu image $ubuntu_image_local"
    if ! (lxc image info $ubuntu_image_local 2>/dev/null | grep -F -q "Architecture:") ; then
        info "  copying Ubuntu image $ubuntu_version locally"
        # NOTE: if it fails to add the aliases, then https://github.com/lxc/lxd/issues/6419
        lxc image copy ubuntu:$ubuntu_version --copy-aliases --auto-update --alias $ubuntu_image_local local: 
    fi
    

    local container=$1

    prepareLxdImageStartContainer $ubuntu_image_local "$container"
    lxdPushShellFiles "$container"
}


lxdPushShellFiles() {
    local container="$1"

    lxcExecDirect "$container" mkdir -p /usr/local/lib/shell
    for f in apt.sh general.sh; do
        lxc file push "$SCRIPT_PATH/lib/$f" "$container/usr/local/lib/shell/"
    done
}


prepareLxdImage__02_kernel_config_file_or_module() {
    local container=$1
    
    f=/boot/config-$(uname -r)
    
    if [ -f "$f" ]; then
    	info "Copying kernel config file $f"
    	lxc file push "$f" "$container/$f"
    	modprobe configs || true 
    else
    	modprobe configs
    fi
}


prepareLxdImage__03_remove_annoying_mesg() {
    local container="$1"
    lxcExecDirect "$container" sed -i -Ee 's@.*mesg\s+n.*@@' /root/.profile
}


prepareLxdImage__50_run_script_inside() {
    local container="$1"

    run_script_inside_container "$container" --setup-inside-lxd-image

}




# ==================================================
# insideLxdImage__* are functions run inside the base LXD image - the ones
# that install docker, kubeadm, kubectl
#

insideLxdImage__03_apt_initial() {
    info "doing an 'apt update'. Can take a couple of minutes."
    apt_update

    apt_install  apt-transport-https ca-certificates curl gnupg software-properties-common
}


insideLxdImage__04_remove_packages() {
    info "Removing some packages"

    # SEEME: we try to gain some disk space. Probably not worth it since later installed docker images will be big anyway
    apt_remove ubuntu-server lvm2 btrfs-tools btrfs-progs command-not-found command-not-found-data \
        mdadm open-vm-tools xfsprogs cryptsetup cryptsetup-bin
    apt_remove dosfstools eject friendly-recovery ftp gdisk git mlocate parted perl libx11-6 popularity-contest \
        ufw
}


insideLxdImage__06_install_conntrack() {
    info "installing conntrack"
    apt_install conntrack
}


insideLxdImage__07_add_docker_repo() {
    info "installing Docker repo key"    
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

    info "adding Docker repo"

    # shellcheck disable=SC2016 disable=SC1091
    add-apt-repository --no-update "deb https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(lsb_release -cs) stable"
    grep -q https://download.docker.com/linux /etc/apt/sources.list
}


insideLxdImage__08_docker_check_variant() {
    
    # verifying that candidate will be from the docker repo
    candidate=$(apt-cache policy docker-ce | grep -F "Candidate")
    candidate=${candidate/Candidate: /}
    if ! apt-cache policy docker-ce | grep -F -A 1 "$candidate" | grep -F download.docker.com/ | grep -F -q download.docker.com/ ; then
        err "Strange, it looks like the docker candidate to install ($candidate) does not come from docker's repo. Please check in: "
        apt-cache policy docker-ce
        exit 1
    fi
}


insideLxdImage__08_add_kubernetes_repo() {
    info "installing Kubernetes repo key"    
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    
    info "adding Kubernetes repo"
    if ! grep -q 'https://apt.kubernetes.io/' /etc/apt/sources.list; then
        add-apt-repository "deb https://apt.kubernetes.io/ kubernetes-xenial main"
    fi

    grep -q https://apt.kubernetes.io /etc/apt/sources.list

    # not needed actually, add-apt-repository does it itself
    #info "doing an 'apt update' to also get Docker and Kubernetes packages info"
    #apt_update_now
}


insideLxdImage__10_install_docker() {
    info "installing Docker"
    
    apt_install docker-ce="${DOCKER_VERSION}*" jq socat 
    sleep 2s # don't recall why :-(

    status=$(systemctl status docker)
    if echo "$status" | grep -qP 'Loaded: loaded \(\S+docker.service: enabled.*Active: active \(running' ; then
        bail "Looks like docker was not activated or was not running? $status"
    fi
    # stop docker, we'll set it up and run later
    service docker stop
}


insideLxdImage__11_install_kubernetes_packages() {
    [ -z "$use_snap" ] || return 0

    info "installing kubeadm, kubectl, kubelet ($K8S_VERSION)"
    
    apt_install kubeadm="$K8S_VERSION*" kubelet="$K8S_VERSION*" kubectl="$K8S_VERSION*" 
}


insideLxdImage__11_install_kubernetes_snap() {
    local container=$1

    [ -n "$use_snap" ] || return 0

    info "installing from snap: kubeadm, kubectl, kubelet ($K8S_VERSION)"
    local vMajMin
    vMajMin=$(echo -n "$K8S_VERSION" | sed -Ee 's@^([0-9]+\.[0-9]+).*@\1@')

    if apt show kubernetes-cni &>/dev/null; then
        apt_install kubernetes-cni
    fi
    
    for n in kubeadm kubelet kubectl; do
        snap install --channel="$vMajMin/stable" "$n" --classic
    done
}


insideLxdImage__11_docker_config() {
    info "creating docker config file"

    # using systemd as cgroup driver: https://kubernetes.io/docs/setup/production-environment/container-runtimes/
    local cfg=/etc/docker/daemon.json
      
    cat >"$cfg" << EOS
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOS
       
    mkdir -p /etc/systemd/system/docker.service.d

    systemctl daemon-reload
    systemctl restart docker
}


insideLxdImage__11_fix_kubernetes_version() {
    [ -z "$use_snap" ] || return 0
    # fixing the kubernetes version. aka "Set it in stone"
    apt-mark hold kubelet kubeadm kubectl
}

insideLxdImage__12_kubernetes_systemd() {
    [ -n "$use_snap" ] || return 0
    info "Setting up kubelet systemd service"

    # don't forget to escape $ (\$)
    local d=/etc/systemd/system
    
    local KUBELET_CONF_FILE=

    test -d "$d/kubelet.service.d" || mkdir -p "$d/kubelet.service.d"
    cat > "$d/kubelet.service.d/10-kubeadm.conf" <<EOS
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
# This is a file that "kubeadm init" and "kubeadm join" generate at runtime, populating
# the KUBELET_KUBEADM_ARGS variable dynamically
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably,
#the user should use the .NodeRegistration.KubeletExtraArgs object in the configuration files instead.
# KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/default/kubelet
EnvironmentFile=-/etc/profile.d/00-proxy.sh
ExecStart=
ExecStart=/snap/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_CONFIG_ARGS \$KUBELET_KUBEADM_ARGS \$KUBELET_EXTRA_ARGS
SyslogIdentifier=kubelet.daemon
Restart=always
#TimeoutStopSec=30
Type=simple

[Unit]
StartLimitIntervalSec=0
StartLimitBurst=0


EOS

    if [ -f "$d/snap.kubelet.daemon.service" ]; then
        mv "$d/snap.kubelet.daemon.service" "$d/kubelet.service"
    else
        # already moved
        test -f "$d/kubelet.service"
    fi

    

    systemctl daemon-reload
    systemctl enable kubelet.service
    systemctl stop kubelet.service
}


insideLxdImage__15_limit_journal_size() {
    info "Setting up some limits on the journald log size"
    
    local d=/etc/systemd/journald.conf.d/
    [ -d "$d" ] || mkdir -p "$d"
    cat > "$d/limits.conf" <<EOS
[Journal]
MaxFileSec=2day
MaxRetentionSec=7day
SystemMaxUse=200M
SystemMaxFileSize=50M
EOS

    systemctl force-reload systemd-journald
}



insideLxdImage__30_docker_start() {
    service docker start
}


# ========================


# separate setup for worker image

prepareLxdImage_worker__01_start_it() {
    local container=$1
    local imageName
    imageName=$(makeValidHostname "${IMAGE_NAME_BASE}-${K8S_VERSION}")
    prepareLxdImageStartContainer "$imageName" "$container"

}

prepareLxdImage_worker__30_inside_script_run() {
    local container="$1"
    run_script_inside_container "$container" --setup-inside-lxd-image-worker
}


# in order to be able to mount nfs mountpoints, at least those provided by nfs-server-provisioner,
# we need the mount.nfs program
#
insideLxdImage_worker__10_nfs_client_install() {
    info "installing nfs client code (to be able to mount nfs volumes)"
    apt_install nfs-common
}

insideLxdImage_worker__20_pull_kubeadm_used_images() {
    info "pulling images used by kubeadm to speed up initialisation"
    
    # worker node does not need all of them, so we get only a few.
    kubeadm --kubernetes-version "$K8S_VERSION" config images list 2>/dev/null | grep -Pv 'apiserver|controller-manager|scheduler|etcd|coredns' | xargs -r -n 1  docker pull        
}


# ====================
# separate setup for master image

prepareLxdImage_master__01_start_it() {
    local container=$1
    local imageName
    imageName=$(makeValidHostname "${IMAGE_NAME_BASE}-${K8S_VERSION}")

    prepareLxdImageStartContainer "$imageName" "$container"
}


prepareLxdImage_master__30_inside_script_run() {
    local container=$1
    run_script_inside_container "$container" --setup-inside-lxd-image-master
}


# the lxd image will grow, but it will not use the network for download later
# plus startup will be much faster
#
insideLxdImage_master__10_pull_kubeadm_used_images() {
    info "pulling images used by kubeadm to speed up initialisation"
    # master needs all of them, so no filtering
    kubeadm --kubernetes-version "$K8S_VERSION" config images pull
}


# ==== cleanup     

prepareLxdImageCleanup__02_remove_some_packages() {
    local container=$1
    
    info "[$container]: Removing unnecessary packages from container $container"

    lxcExec "$container" "${APT_REMOVE[@]}" unattended-upgrades mlocate
}


prepareLxdImageCleanup__04_cleanup() {
    local container=$1
    
    # cleaning up in the image:
    info "[$container]: Cleaning up space in container $container..."

    lxcExec "$container" apt-get clean
    lxcExec "$container" rm -f /etc/dpkg/dpkg.cfg.d/02apt-speedup
    #lxcExecBash "$container" "rm -rf /var/lib/apt/lists/*"
    lxcExec "$container" rm -rf /build
    # not very sure yet :-)
    lxcExecBash "$container" "rm -rf /var/lib/dpkg/*-old"

    # definitely
    lxcExecBash "$container" "rm -rf /var/lib/apt/lists/ /var/cache/apt/*.bin"
    lxcExecBash "$container" "rm -rf /var/lib/mlocate/ /var/lib/snapd/cache/*"
    lxcExecBash "$container" "rm -rf /tmp/* /var/tmp/*"
    lxcExecBash "$container" "rm -rf /usr/share/doc/* /usr/share/man/* /var/cache/man/"
}

prepareLxdImageCleanup__06_cleanup_logs() {
    local container=$1
    
    info "[$container]: Cleaning up logs from container $container"
    
    lxcExecBash "$container" "rm -rf /var/log/*.log"
    lxcExecBash "$container" "journalctl --flush; journalctl --rotate; journalctl -m --vacuum-time=1s"
}	


# =======================================
publishContainerAsImage() {
    local container=$1

    info "Publishing locally the k8s container '$container' as image '$container'"
    lxc stop "$container"
    lxc publish "$container" --alias "$container" --compression none
    
    lxc delete "$container"
}


buildLxdCommonImage() {
    local container
    container=$(makeValidHostname "$IMAGE_NAME_BASE-${K8S_VERSION}")

    local imageName
    imageName=$(makeValidHostname "${IMAGE_NAME_BASE}-${K8S_VERSION}")
    if lxcCheckImageExists "$imageName" ; then
    	#TODO: version check
    	info "Image '$imageName' already present, not building"
        return 0
    fi
    
    runFunctions '^prepareLxdImage__' "$container"

    publishContainerAsImage "$container"
}


buildLxdOneImage() {
    local type=$1 # master or worker
    
    buildLxdCommonImage
    
    local container
    container=$(makeValidHostname "${IMAGE_NAME_BASE}-${K8S_VERSION}-${type}")
    
    runFunctions "^prepareLxdImage_${type}__" "$container"
    runFunctions '^prepareLxdImageCleanup__' "$container"

    publishContainerAsImage "$container"
}


buildLxdMasterImage() {
    buildLxdOneImage "master"
}


buildLxdWorkerImage() {
    buildLxdOneImage "worker"
}


 
prepareLxdImages() {
    ensureLxdIsInstalled
    
    # we want 2 type of images: one for the master and one for the worker.
    # when building them, we're going to have, until a certain point, some common
    # setup
    
    
    local master_image
    master_image=$(makeValidHostname "${IMAGE_NAME_BASE}-${K8S_VERSION}-master")
    
    if lxcCheckImageExists "$master_image" ; then
        #TODO: version check
        info "Image '$master_image' already present, not building"
    else
        buildLxdMasterImage        
    fi

    local worker_image
    worker_image=$(makeValidHostname "${IMAGE_NAME_BASE}-${K8S_VERSION}-worker")

    if lxcCheckImageExists "$worker_image" ; then
        #TODO: version check
        info "Image '$worker_image' already present, not building"
    else
        buildLxdWorkerImage        
    fi
    
    # delete the common image now
    local base_image
    base_image=$(makeValidHostname "${IMAGE_NAME_BASE}-${K8S_VERSION}")
    if lxc image show "$base_image" 2>/dev/null | grep -F -q 'public:' ; then 
        lxc image delete  "$base_image"
    fi
}

