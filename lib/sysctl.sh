# shellcheck shell=bash

SYSCTL_CONF_FILE=/etc/sysctl.d/99-lxd-k8s.conf


sysctlFileSet() {
    name=$1
    value=$2
    
    if test -f $SYSCTL_CONF_FILE && grep -E -q "^\s*$name\s*=" "$SYSCTL_CONF_FILE" ; then
        local oldV
        oldV=$(grep -E "^\s*$name\s*=" "$SYSCTL_CONF_FILE" | sed -Ee "s@^\s*$name\s*=\s*(\S+)@\1@")
        if [ "$oldV" != "$value" ]; then
            sudo sed -i -Ee "s@^\s*$name\s**=.*@$name=$value@" "$SYSCTL_CONF_FILE"
        fi
    else
        echo "$name=$value" | sudo bash -c "cat >> $SYSCTL_CONF_FILE"
    fi
}


sysctlSetIfTooSmall() {
    name=$1
    minValue=$2

    info "  checking for sysctl $name >= $minValue"
    n=$(sysctl -n "$name")
    if [[ $n -lt $minValue ]]; then
        warn "    value is too small ($n). Updating"
        sysctlFileSet "$name" "$minValue"
        return 1
    fi
    return 0
}


sysctlSet() {
    name=$1
    value=$2

    info "  checking for $name=$value"
    n=$(sysctl -n "$name")
    if [[ "$n" != "$value" ]]; then
        warn "    needs to be updated to $value"
        sysctlFileSet "$name" "$value"
        return 1
    fi
    return 0
}


sysctlLoadFile() {
    sudo -i sysctl -p "$SYSCTL_CONF_FILE"
}    
