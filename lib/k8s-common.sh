# shellcheck shell=bash
# common functionality for a master and worker node
#
# needs $LXD_PROFILE_NAME and various functions
#

# GLOBAL const
#shellcheck disable=SC2034
TMP_KUBEADM_CONFIG="/tmp/kubeadm.config.yaml"


master_container() {
    local prefix=$1
    echo "$prefix-master"
}


runKubectl() {
    ensureClusterNameIsSet
    kubectl --context "lxd-$CLUSTER_NAME" "$@"
}

runningKubernetesMajMinVersion() {
    runKubectl version -o json | jq -r '.serverVersion|.major + "." + .minor'
}


# full X.Y.Z version of running cluster
runningKubernetesVersion() {
    local majMin=
    majMin=$(runningKubernetesMajMinVersion)
    local gitVers
    gitVers=$(runKubectl version -o json | jq -r '.serverVersion.gitVersion | ltrimstr("v")' )

    [[ "$gitVers" = "$majMin."* ]] || bail "strange version information given by kubectl version -o json"

    echo "$gitVers"
}


removeServiceProxy() {
    local ns="$1"
    local serviceName="$2"

    lxc config device remove "${CLUSTER_NAME}-master" "proxy-svc-$ns-$serviceName" 2>/dev/null || true
}


addServiceProxy() {
    local ns="$1"
    local serviceName="$2"

    ip=$(runKubectl get service "$serviceName" -n "$ns" -o jsonpath='{.spec.clusterIP}')
    port=$(runKubectl get service "$serviceName" -n "$ns" -o jsonpath='{.spec.ports[0].port}')

    local localPort

    local crtConnect
    crtConnect=$(lxc query "/1.0/containers/${CLUSTER_NAME}-master" | jq -r ".devices | to_entries | .[] | select( .key == \"proxy-svc-$ns-$serviceName\") | .value.connect")
    if [ -z "$crtConnect" ]; then
        localPort=$(getRandomLocalPort)
        lxc config device add "${CLUSTER_NAME}-master" "proxy-svc-$ns-$serviceName" proxy listen="tcp:0.0.0.0:$localPort" connect="tcp:$ip:$port" bind=host
        info "Adding LXD proxy device. "
    elif [ "$crtConnect" = "tcp:$ip:$port" ]; then
        localPort=$(lxc query "/1.0/containers/${CLUSTER_NAME}-master" | jq -r ".devices | to_entries | .[] | select( .key == \"proxy-svc-$ns-$serviceName\") | .value.listen | ltrimstr(\"tcp:0.0.0.0:\") ")

        info "LXD proxy device already present."
    else 
        info "LXD proxy device already present, changing service IP"
        localPort=$(lxc query "/1.0/containers/${CLUSTER_NAME}-master" | jq -r ".devices | to_entries | .[] | select( .key == \"proxy-svc-$ns-$serviceName\") | .value.listen | ltrimstr(\"tcp:0.0.0.0:\") ")
        lxc config device set "${CLUSTER_NAME}-master" "proxy-svc-$ns-$serviceName" connect="tcp:$ip:$port"
    fi

    local proto="https?"
    [ "$port" == "443" ] && proto="https"

    local crtIP
    crtIP=$(getIpOfNetDevice "$(getNetDevice)")

    info "Use $proto://localhost:$localPort or even $proto://$crtIP:$localPort (from other machines)  to access your ${serviceName}:${port} service"
}



launchK8SContainer() {
    local container="$1"
    local image_name="$2"
    local masterContainer="$3"

    ensureLxdImageExists "$image_name"
    
    if lxdContainerExists "$container"  ; then
        err "LXD Container $container exists. Please stop and delete it first"
        info "  lxc stop $container; lxc delete $container"
        exit 1
    fi

    # Not sure who the f. sends something on stdin, inside vagrant. https://github.com/lxc/lxd/issues/6228
    lxc init -p "$LXD_PROFILE_NAME" "$image_name" "$container"  < /dev/null

    # one time setup before container actually starts:
    if [ "$container" = "$masterContainer" ]; then
        runFunctions '^init_before_master_starts__' "$masterContainer"
    else
        runFunctions '^init_before_worker_starts__'  "$container" "$masterContainer"
    fi

    # things that are running always before a container is started, wether after being created or during its normal
    # lifetime
    runFunctions '^before_node_starts__' "$masterContainer" "$container"

    lxc start "$container"
    lxdWaitIp "$container"

    info "Container has an IP address. Waiting for Docker to start"
    # and wait for Docker service to be ready since you'll want to use it soon after start
    for _ in $(seq 1 10); do
        if lxcExec "$container" service docker status | grep -F -q 'Active: active (running)' ; then
            break
        fi
        sleep 1s
    done
    info "Container ready for next setup phases"
}


checkResources() {
    declare -i usedDisk
    usedDisk=$(df -l --output=pcent  / | tail -n 1 | sed -e 's/[ %]//g')
    if [ "$usedDisk" -ge 80 ]; then
        # 90% is the default but since we're going to also add some images, lets be conservative
    	warn "Kubernetes node might not start due to disk pressure (not enough free space, 20%) on your host '/' filesystem"
        warn "  Now you're using $usedDisk%"
        exit 1
    fi 
}



# @param container : container in which to wait for node to be declared ready (usually the 'master' node)
# @param nodeName - obvious, right?
#
waitNodeReady() {
    local container=$1
    local nodeName=$2

    info "Waiting for kubernetes node to be declared as ready"
    
    lxcExecBashCommands "$container" <<EOS
    
info() {
    echo "INFO: " \$@
}
warn() {
    echo "WARN: " \$@
}
err() {
    echo "ERR:  " "\$@"
}
bail() {
    err "\$@"
    exit 1
}

export KUBECONFIG=/etc/kubernetes/admin.conf
for i in \$(seq 1 60) ; do
    ready=\$(kubectl get node $nodeName -o json | jq '.status.conditions|map(select(.type == "Ready"))[0].status')

    if [ "\$ready" == '"True"' ]; then
        break;
    fi

    if kubectl get node $nodeName -o jsonpath='{range .status.conditions[*]}{.type}{","}{.status}{"\n"}{end}' | grep -qE 'Pressure,True' ; then
        err "It looks like you are low on resources. See output below "
        kubectl get node $nodeName -o jsonpath='{range .status.conditions[*]}{.type}{","}{.status}{"\n"}{end}'
        bail "Fix the problem, remove this node, and recreate it"
    fi

    info "node $nodeName 'ready status': \$ready. Sleeping 5s"
    sleep 5s
done

if [ "\$ready" != '"True"' ]; then
    warn "After many tries, node is still not declared as ready. You should check the logs inside it."
    warn "Do an 'lxc exec \$nodeName journalctl'"
    warn "One possible reason: disk pressure"
    exit -1
else
    info "node $nodeName is ready."
fi

EOS

}


disableCniNetorking() {
    local container=$1

    info "Disabling CNI networking "
    lxcExec "$container" sed -i 's/--network-plugin=cni //' /var/lib/kubelet/kubeadm-flags.env
    lxcExec "$container" systemctl daemon-reload
    lxcExec "$container" systemctl restart kubelet
}
	

installCniNetwork() {
    local container=$1

    # networking cni plugin
    lxcExecBash "$container" "export KUBECONFIG=/etc/kubernetes/admin.conf ; kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
}


setupCniNetwork() {
    local container=$1
    mode=$2 # master or worker

    test "$mode" == "worker" && return 0
    
    # for multinode, we need a cni plugin.
    # if you're going to use a single node, you can let it call 'disableCniNetworking'

    if false ; then
        disableCniNetorking  "$container"
    else
        installCniNetwork "$container"
    fi
}



kubeletChangeAuthMode() {
    local container=$1

    f=/etc/default/kubelet
    var=KUBELET_EXTRA_ARGS

    info "  changing authorization mode for Kubelet"
    lxcChangeVarInFile "$container" $f $var authorization-mode Webhook    
    lxcChangeVarInFile "$container" $f $var authentication-token-webhook true

    lxcExec "$container" systemctl restart kubelet
}


enjoyMsg() {
    info "Enjoy your kubernetes experience!"
    info "Feel free to report bugs, feature requests and so on, at https://github.com/cr1st1p/k8s-on-lxd/issues"
}

    
