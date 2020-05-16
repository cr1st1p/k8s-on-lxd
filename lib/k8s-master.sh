# shellcheck shell=bash

# Setting up a master node
#
# launch_master__* functions will get the prefix of the cluster and the master container name
# as parameters
#
# 0 - create container
# < 20 - setup kubeadm + run kubeadm
# 20 wait node ready
# >= 30 after node is ready
#




launch_master__00_start_it() {
    local prefix=$1
    local container=$2

    info "  creating container, for kubernetes version $K8S_VERSION"
    checkResources
    local imageName
    imageName=$(makeValidHostname "${IMAGE_NAME_BASE}-${K8S_VERSION}-master")
    launchK8SContainer "$container" "$imageName" "$container"
}


generateKubeadmToken() {
    checkForCommand pwgen
    
    p1=$(pwgen 6 -A 1)
    p2=$(pwgen 16 -A 1)
    token="$p1.$p2"
    echo -n "$token"
}


init_before_master_starts__10_set_eth_fixed_ip() {
    local container="$1"

    info "   Setting a fixed IP to master container"
    local intf
    intf=$(lxdGetHostInterface)

    # let's find a suitable unused IP. Assuming we set LXD's dhcp to leave some available
    local url="/1.0/networks/$intf"
    local cidr
    cidr=$(lxc query "$url" | jq -r '.config["ipv4.address"]')
    local base
    base=$(echo "$cidr" | cut -d '.' -f 1-3)
    declare -i min
    min=$((1 + $(echo "$cidr" | cut -d '.' -f 4 | cut -d '/' -f 1)))

    local dhcp_ranges
    dhcp_ranges=$(lxc query "$url" 2>/dev/null | jq -r '.config["ipv4.dhcp.ranges"]')
    if [[ "$dhcp_ranges" != *"-"* ]]; then
        bail "Invalid DHCP range $dhcp_ranges"
    fi
    declare -i max
    max=$(( $(echo "$dhcp_ranges" | cut -d '-' -f 1 | cut -d '.' -f 4) - 1))

    if (( "$min" > "$max" )); then
        bail "Something bad happened. Found IP min to be $min, and max to be $max !? cidr=$cidr, dhcp_ranges=$dhcp_ranges"
    fi

    local ftmp
    ftmp=$(mktemp)

    for url in $(lxc query /1.0/containers | jq -r '.[]'); do
        local name
        name=$(lxc query "$url" | jq -r '.name')

        local c_ip
        c_ip=$(lxdGetConfiguredIp "$name")
        [ -n "$c_ip" ] && echo "$c_ip" >> "$ftmp"
        c_ip=$(lxdGetIp "$name")
        [ -n "$c_ip" ] && echo "$c_ip" >> "$ftmp"        
    done

    for i in $(seq $min $max) ; do
        local ip
        ip="$base.$i"

        if ! grep "^$ip\$" "$ftmp" ; then
            lxdSetFixedIp "$container" "$ip" "$intf"
            rm "$ftmp"
            return 0
        fi
    done
    rm "$ftmp"
    bail "Could not find a free IP between $base.$min and $base.max"
}


launch_master__02_generate_kubeadm_token() {
    local prefix=$1
    local container=$2

    token=$(generateKubeadmToken)
    lxc config set "$container" user.kubeadm.token "$token"

}


launch_master__04_create_kubeadm_config() {
    local prefix=$1
    local container=$2

    info "  creating kubeadm config file"

    # let's prepare kubeadm config - we need more than command args can support
    # FIXME: MaxPerCode still not taken into account
    # FIXME: and probably also not podSubnet. Also, can not combine --config and cmd line parameters
    # To see the defaults: 
    #  kubeadm config print init-defaults --component-configs KubeletConfiguration  

    cfg=$(mktemp)

    local KUBEADM_API_VERSION
    local KUBELET_API_VERSION

    if verlt "$K8S_VERSION" "1.18" ; then
        KUBEADM_API_VERSION=kubeadm.k8s.io/v1beta1
        KUBELET_API_VERSION=kubelet.config.k8s.io/v1beta1
    else
        KUBEADM_API_VERSION=kubeadm.k8s.io/v1beta2
        KUBELET_API_VERSION=kubelet.config.k8s.io/v1beta1
    fi
    
    cat >"$cfg" << EOS
apiVersion: $KUBEADM_API_VERSION
kind: InitConfiguration
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: $token
  ttl: "0"
  usages:
  - signing
  - authentication
# Supported from v1beta2 onward (kubeadm 1.15+)
#nodeRegistration:
#  ignorePreflightErrors:
#  - FileContent--proc-sys-net-bridge-bridge-nf-call-iptables
---
kind: ClusterConfiguration
apiVersion: $KUBEADM_API_VERSION
apiServer:
  timeoutForControlPlane: 4m0s
  certSANs:
  - ${prefix}-master.lxd
kubernetesVersion: v${K8S_VERSION}
certificatesDir: /etc/kubernetes/pki
networking:
  dnsDomain: cluster.local
  podSubnet: 10.244.0.0/16
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
Conntrack:
  MaxPerCore: 0
ClusterCIDR: 10.244.0.0/16
---
apiVersion: $KUBELET_API_VERSION
kind: KubeletConfiguration
failSwapOn: false
---
EOS
       
    lxc file push "$cfg" "$container/$TMP_KUBEADM_CONFIG"
    rm "$cfg"
}


launch_master__08_run_kubeadm() {
    local prefix=$1
    local container=$2

    info "  running kubeadm"


    local ignore
    ignore=$(kubeadmCommonIgnoredPreflightChecks)

    kubeAdmParams=("--ignore-preflight-errors=$ignore")
    
    #kubeAdmParams+=(--token "$token" --token-ttl 0)
    #kubeAdmParams+=(--pod-network-cidr 10.244.0.0/16)
    #kubeAdmParams+=(--kubernetes-version "$K8S_VERSION")
    
    kubeAdmParams+=(--config "$TMP_KUBEADM_CONFIG")

    #kubeAdmParams+=(--apiserver-cert-extra-sans "${prefix}-master.lxd")

    lxcExec "$container" kubeadm init "${kubeAdmParams[@]}"
    lxcExec "$container" rm "$TMP_KUBEADM_CONFIG"
}


launch_master__10_setup_network() {
    local prefix=$1
    local container=$2

    setupCniNetwork "$container" master
}

launch_master__20_wait_node_ready() {
    local prefix=$1
    local container=$2

    waitNodeReady "$container" "$container"
    # TODO: check outcome of node ready
}


# needed to install kube-prometheus for example
exposeKubernetesController() {
    local container=$1

    info "  exposing kubernetes controller"
    # DO NOT forget to backquote $
    lxcExecBashCommands "$container" <<EOS
    for n in controller-manager scheduler ; do
        sed -e 's/- --address=127.0.0.1/- --address=0.0.0.0/' -i \
            /etc/kubernetes/manifests/kube-\${n}.yaml
    done

EOS


}


launch_master__30_expose_controller() {
    local prefix=$1
    local container=$2

    if [ "$EXPORT_KUBECONTROLLER" == "1" ]; then
        exposeKubernetesController "$container"
    fi
}


launch_master__32_change_auth_mode() {
    local prefix=$1
    local container=$2

    if [ "$KUBELET_AUTH_CHANGE" == "1" ]; then
        kubeletChangeAuthMode "$container"
    fi
}


launch_master__34_single_coredns() {
    local prefix=$1
    local container=$2

    # on local box, no need for 2 replicas...
    info "  scaling CoreDns to 1 replica - no need for 2 replicas..."
    lxcExecBash "$container" "export KUBECONFIG=/etc/kubernetes/admin.conf; kubectl scale -n kube-system deployment --replicas 1 coredns"
}



launchMaster() {
    local prefix=$1

    local container
    container=$(master_container "$prefix")

    info "Creating a master node: $container"

    lxdCheckProfileVersion
    
    runFunctions '^launch_master__' "$prefix" "$container"

    addUserKubectlConfig "$prefix"

    info "Node '$container' added!"
    info ""
    runFunctions '^messages_master_node__' "$prefix" "$container"

    enjoyMsg
}

