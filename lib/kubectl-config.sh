# shellcheck shell=bash
# extract info from the container(s) and set things up in your local kubectl config
# so that you can easily access your new cluster
#


getKubeadmConfigEntry() {
    local container=$1
    field=$2
    dest="$3-$field"

    lxcExec "$container" fgrep "$field:" /etc/kubernetes/admin.conf | sed -sE "s/^\s*\S+:\s*//" | base64 -d > "$dest"
}


addUserKubectlConfig() {
    prefix=$1
    local container="${prefix}-master"

    info "Will extract information so that you can access it directly with your kubectl program"

    if ! type -P kubectl &>/dev/null; then
        warn "You need to have 'kubectl' program installed, so this step will be skipped"
        return 0
    fi

    lxcCheckContainerIsRunning "$container"

    local ctxName="lxd-${prefix}"
    
    where="$HOME/.kube/"
    test -d "$where" || mkdir -p "$where"
    where="${where}/config-$ctxName"
    
    getKubeadmConfigEntry "$container" "certificate-authority-data" "$where"
    getKubeadmConfigEntry "$container" "client-certificate-data" "$where"
    getKubeadmConfigEntry "$container" "client-key-data" "$where"
    
    if lxdRemoteIsLocal; then
        apiIP=$(lxdGetIp "$container")
        apiPort=6443
    else
        local remoteHost
        remoteHost=$(hostnameFromUrl "$(lxdRemoteUrl "$LXD_REMOTE")")
        if [ -z "$remoteHost" ]; then
            warn "Could not determine $LXD_REMOTE remote's hosstname!?"
            return 0
        fi
        apiIP="$remoteHost"
        apiPort=$(lxc query "$LXD_REMOTE/1.0/containers/${container}" | jq -r '.devices | to_entries | .[] | select( .key == "proxy-api") | .value.listen' | grep '^tcp:0.0.0.0:' | sed -E -e 's@tcp:0.0.0.0:@@')
    fi


    kubectl config set-cluster --context "$ctxName" "$ctxName" \
        --server  "https://$apiIP:$apiPort" \
        --certificate-authority "${where}-certificate-authority-data"
    kubectl config set-credentials --context "$ctxName" "$ctxName" \
        --client-certificate "${where}-client-certificate-data" \
        --client-key "${where}-client-key-data" 
    kubectl config set-context "$ctxName" --context "$ctxName" --cluster "$ctxName" --user "$ctxName"

    info "To use your new LXD kubernetes cluster you can either "
    info " - switch the default context to be used via: kubectl config use-context $ctxName"
    info " - or, always specifying the context, like in: kubectl --context $ctxName get pod "
    # cat ~/.kube/config
}


