#shellcheck shell=bash

addon_proxy_cache_info() {
    info "This will set LXD container environment to use the proxy variables found in your environment (host)"
    warn "Setup works, but other than that ... you can expect other problems to popup :-( "
}

# this should work on a STOPPed container!
lxdContainerUpdateProxyFile() {
    local container=$1
    shift

    local f_destination=/etc/profile.d/00-proxy.sh
    local f_local
    f_local=$(mktemp)

    info "Checking for proxy setup ..."
    cat > "$f_local" << EOS
# Main  settings for http proxy variables
# MANDATORY: keep them in a=b format
# Automatically updated when you start the container via the script

EOS

    local CIDR_TO_IGNORE
    CIDR_TO_IGNORE=$(lxdGetHostIpCidr)

    # check if proxies are really working:
    #shellcheck disable=SC2154
    if [ -n "$http_proxy" ]; then
        curl --head http://google.com >/dev/null 2>/dev/null 
    fi    
    #shellcheck disable=SC2154    
    if [ -n "$https_proxy" ] || [ -n "$HTTPS_PROXY" ]; then
        curl --head https://google.com >/dev/null 2>/dev/null 
    fi

    
    for name in http_proxy https_proxy no_proxy; do
        local value=${!name}
        if [ -n "$value" ]; then
            info "    detected env var '$name'"
            if [ "$name" = "no_proxy" ]; then
                # lets ensure a few things are in there.
                # note that not all programs know to use CIDRs from it
                for v in "127.0.0.1" "localhost" "*.lxd" "10.0.0.0/24", "172.0.0.0/8" "$CIDR_TO_IGNORE" "$@"; do
                    [[ "$value" = *"$v"* ]] || value="$value,$v"
                done
            fi
            echo "$name=\"$value\"" >> "$f_local"
        fi
    done
    info "    pushing file $f_destination"
    lxc file push "$f_local" "$container/$f_destination"
}


prepareLxdImage__10_01_global_http_proxy() {
    local container=$1

    lxdContainerUpdateProxyFile "$container"
}

before_node_starts__01_proxy() {
    local masterContainer="$1"
    local container="$2"

    lxdContainerUpdateProxyFile "$container"
}


# prepareLxdImage__10_http_proxy_copy_script() {
#     local container=$1
#     local d=/usr/local/bin
#     lxcExecBash "$container" "test  -d '$d'  || mkdir -p '$d' "
#     lxc file push $SCRIPT_PATH/addons/proxy-cache/update-http-proxy.sh "$container/usr/local/bin/"
#     lxcExec "$container" chown +x "$d/update-http-proxy.sh"
# }



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



setup_docker_proxy() {
    setServiceProxyEnvironment "docker"
}

insideLxdImage__10_z_docker_proxy() {
    setServiceProxyEnvironment "docker"
}


# https://bugs.launchpad.net/ubuntu/+source/snapd/+bug/1579652
# grr.
insideLxdImage__10_z_snapd_proxy() {
    setServiceProxyEnvironment "snapd"
    systemctl restart snapd.service
}


messages_master_node__01_proxy_warn() {
    local prefix=$1
    local container="$2"

    if [ -n "$http_proxy" ] || [ -n "$https_proxy" ] || [ -n "$HTTP_PROXY" ] || [ -n "$HTTPS_PROXY" ]; then
        local containerIP
        containerIP=$(lxdGetIp "$container")

        # kubectl seem to use the upper case named variant
        if [[ "$NO_PROXY" != *"$containerIP"* ]]; then
            warn "PROXY setup: need to ensure no_proxy contains your lxc container IP address $containerIP"
            warn "I can't check all CIDRs from no_proxy, you should double check that either $containerIP is"
            warn "included as-is in the no_proxy environment variable, or covered by some CIDR range in it."
            warn "Otherwise you might not be able to reach your cluster."
            warn "Alternative, disable proxy when running kubectl, like:"
            warn "http_proxy= https_proxy= kubectl --context lxd-$prefix ...."
        fi
    fi
}


