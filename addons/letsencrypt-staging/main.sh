#shellcheck shell=bash

ADDON_LETSENCRYPT_STAGING="Letsencrypt Staging"

addon_letsencrypt_staging_info() {
    cat <<EOS
$ADDON_LETSENCRYPT_STAGING - setup certificate inside LXD containers so that dockerd (at least)
accepts secure urls to sites with certificate from Letsencrypt Staging.
Example case:
You run a docker registry service, secure it with Letsencrypt Certificate and you want to be able
to use it.

Enable it with:

k8s-on-lxd.sh --addon letsencrypt-staging --name CLUSTER_NAME --addon-run install

EOS
}


_addon_letsencrypt_staging_enabled() {
    local v
    v=$(lxc config get "${CLUSTER_NAME}-master" user.letsencrypt_staging.install_cert)
    [ "$v" == "1" ] || return 1
    return 0
}


addon_letsencrypt_staging_install() {
    ensureClusterNameIsSet

    lxc config set "${CLUSTER_NAME}-master" user.letsencrypt_staging.install_cert 1

    for c in $(lxcListByPrefixAll "$CLUSTER_NAME") ; do
        _addon_letsencrypt_staging_setup_container "$c"
    done

}


_addon_letsencrypt_staging_setup_container() {
    local container="$1"


    info "Setting up container '$container' for $ADDON_LETSENCRYPT_STAGING ... "

    lxcExecBashCommands "$container" << 'EOS'
        #set -x

        N="letsencrypt-staging.crt"
        D="/usr/local/share/ca-certificates"

        certInstalled() {
            [ -L "/etc/ssl/certs/$N" ] || [ -L "/etc/ssl/certs/${N/.crt/.pem}" ]
        }


        if certInstalled ; then
            echo "  already installed"
            exit 0
        fi

        # SEEME: ensure curl and openssl tools are installed
                
        [ -d "$D" ] || mkdir -p "$D"

        if [ ! -f "$D/$N" ]; then        
            curl --silent http://cert.stg-root-x1.letsencrypt.org/ | openssl x509 -inform der -outform pem -text > "$D/$N"
        fi

        update-ca-certificates
        if [ ! certInstalled ]; then
            echo " ERROR: a symlink should have appeared in /etc/ssl/certs"
            exit -1
        fi
        service docker restart

EOS

}

# hook ourselves in creation of other machines
launch_worker__02_letsencrypt_staging_setup() {
    #local prefix=$1
    #local masterContainer=$2
    local container=$3

    _addon_letsencrypt_staging_enabled || return 0

    _addon_letsencrypt_staging_setup_container "$container"
}
