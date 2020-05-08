#shellcheck shell=bash
# possible values: auto, disabled
#apt_proxy_cache_mode=auto

addon_apt_proxy_cache_info() {
    cat <<EOS

This addon will just enable use of your APT proxy cache, inside the LXD images, during setup, hopefully
making things faster.
It will check for the environment variable 'apt_proxy_cache' - i.e. if you have a dedicated APT proxy cache
server.
Other parts of the system will set http(s)_proxy variables if needed.

Later, you can update the settings, by running: --name NAME --addon apt-proxy-cache  --addon-run update

EOS
}


addon_apt_proxy_cache_get_proxy() {
    local proxy=""
    #shellcheck disable=SC2154
    if [ -n "$apt_proxy_cache" ]; then
        proxy="$apt_proxy_cache"
    #elif [ -n "$http_proxy" ]; then
    #    proxy="$http_proxy"
    fi

    # let's see if we need some fixes though
    if [[ $proxy =~ "^https?://localhost" ]]; then
        local hostIP
        hostIP=$(lxdGetHostIp)
        proxy=$(echo "$proxy" | sed -E -s "s@(https?://)localhost@\1$hostIP@")
        fi
    echo "$proxy"
}


# this is the function that actually sets or removes the proxy information inside the container
addon_apt_proxy_update_() {
    local container=$1
    local proxy=$2

    apt_proxy_cache_file=/etc/apt/apt.conf.d/02-cache
    if [ -n "$proxy" ]; then
        echo -e "Acquire::http::Proxy \"$proxy\";\nAcquire::HTTPS::Proxy \"$proxy\";\n" \
            | lxcExecBashWithStdin "$container" "cat > $apt_proxy_cache_file" 
    else
        lxcExecBash "$container" "rm $apt_proxy_cache_file 2>/dev/null || true"
    fi
}


# hook ourselves 
prepareLxdImage__11_apt_proxy_cache() {
    local container=$1

    local proxy
    proxy=$(addon_apt_proxy_cache_get_proxy)

    info "Proxy setup for APT"

    addon_apt_proxy_update_ "$container" "$proxy"
}


addon_apt_proxy_cache_update() {
    local proxy
    proxy=$(addon_apt_proxy_cache_get_proxy)

    info "Updating proxy, value is [$proxy]"

    for n in $(lxcListByPrefixRunning "$CLUSTER_NAME"); do
        info "  updating $n ..."
        addon_apt_proxy_update_ "$n" "$proxy"
    done
}

