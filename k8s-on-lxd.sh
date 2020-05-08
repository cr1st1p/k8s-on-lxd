#! /bin/bash

set -e # bail out on errors

#set -x # debug. Or just --debug

# Author: Cristian Posoiu cristi@posoiu.net
#


SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export SCRIPT_PATH
SCRIPT_NAME="$( basename "${BASH_SOURCE[0]}")"
export SCRIPT_NAME

DEBUG=

addon=""
CLUSTER_NAME=""

#shellcheck disable=2034
LXD_PROFILE_NAME=k8s
#shellcheck disable=2034
IMAGE_NAME_BASE=k8s
#shellcheck disable=2034
VERSION=0.4


K8S_VERSION_DEFAULT="1.18.2"
K8S_VERSION="$K8S_VERSION_DEFAULT"


if [[ "$K8S_VERSION" == "1.13"* ]]; then
    DOCKER_VERSION=18.06
elif [[ "$K8S_VERSION" == "1.18"* ]]; then
    #shellcheck disable=2034
    DOCKER_VERSION="5:19.03"
else    
    #shellcheck disable=2034
    DOCKER_VERSION=18.09
fi

# TODO: move this out
# 1 to expose kube-controller-manager and kube-scheduler (i.e. make it listen
# on all interfaces instead of 127.0.0.1). 
# Scope: allow to run kube-prometheus
#shellcheck disable=2034
EXPORT_KUBECONTROLLER=${K8S_EXPOSE_KUBECONTROLLER:-1}

# TODO: move this out
# change authorization mode of kubelet.
# Scope: allow to run kube-prometheus
#shellcheck disable=2034
KUBELET_AUTH_CHANGE=${K8S_AUTH_CHANGE:-1}

#shellcheck disable=SC1090
for f in "$SCRIPT_PATH"/lib/*.sh; do
    source "$f"
done


# load addons
addons=()
addonsDir="$SCRIPT_PATH/addons"
for d in "$addonsDir"/* ; do
    [ -d "$d" ] || continue
    addons+=("$(basename "$d")")
    #shellcheck disable=1090
    source "$d/main.sh"
done



prepareLxd() {
    runFunctions '^setup_host__'

    runFunctions '^setup_lxd__'

    lxdCreateProfile

    prepareLxdImages
}




stopAll() {
    prefix=$1
    
    declare -a list
    mapfile -t list < <(lxcListByPrefixRunning "$prefix")
    if [  "${#list[@]}" -eq 0 ]; then
    	info "No containers to stop"
    else
    	info "Will stop containers" "${list[@]}"
    	lxc stop "${list[@]}"
    fi 
}


runAll() {
    prefix=$1

    mapfile -t list  < <(lxcListByPrefixStopped "$prefix")
    if [ "${#list[@]}" -eq 0 ]; then
    	info "No containers to run"
    else
    	info "Will start containers " "${list[@]}"
        local masterContainer="$prefix-master"
        for container in "${list[@]}"; do
            runFunctions '^before_node_starts__' "$masterContainer" "$container"

    	    lxc start "$container"
        done
    fi 
}


deleteAll() {
    prefix=$1
    
    mapfile -t list < <(lxcListByPrefixRunning "$prefix")
    if [ "${#list[@]}" -ne 0 ]; then
    	info "You have to stop first the containers. Use -S $prefix "
    else
    	mapfile -t list < <(lxcListByPrefixAll "$prefix")
    	if [ "${#list[@]}" -eq 0 ]; then
    		info "No containers to delete"
    	else
	    	info "Will delete containers" "${list[@]}"
	    	lxc delete "${list[@]}"
	fi
    fi
}



usage() {
    cat <<EOS
$SCRIPT_NAME: Running multiple Kubernetes clusters, multi-node, multiple 
versions... on a single machine. Development purpose only.

Usage: $SCRIPT_NAME options...

    -n,--name= NAME : sets the name prefix to use for nodes. Nodes will be named NAME-master, NAME-worker-1, NAME-worker-2, etc
    --k8s-version VERSION : which kubernetes version to use. Default is $K8S_VERSION_DEFAULT
        Usable during setup phase, and when launching a master node.
    -s,--setup:     to prepare lxd setup + an lxd image 
    -m, --master :  to create and start a master node, named NAME-master
    -w, --worker :  to create and start a new worker node, named NAME-worker-N, where N is a number NOT used yet

    -c,--set-config : to update your local kubectl config to access the LXD k8s cluster
            This is done also during creation of the master node.

    -S,--stop :    stop all the containers in the named cluster (master and workers)
    -R,--run :      start all the containers for the named cluster (master and workers)
    -D,--delete :   deletes all the containers for the named cluster (master and workers) - first stop them!

    Others:
    --no-check-lost-found: during setup phase, do not check for presence of lost+found directory

    Addons:
    --addon ADDON_NAME  : always needed
    --addon-info : it will display some information from the addon (if provided by the addon)
    --addon-list : list the addons
    --addon-run COMMAND : it will run specified command from the addon

    Some addons could be more like plugins - i.e. they don't provide commands to run but they plug into the steps run 
    for various phases (setting up the LXD base images for example)
EOS
}

checkArg () {
    if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
        bail "Expected argument for option: $1. None received"
    fi
}

checkAddonArgument() {
    [ -n "$addon" ] || bail "Need to tell me the name of the addon via --addon NAME"
}


declare -i processedArgumentsCount=0

processMainArguments() {
    processedArgumentsCount=0

    case "$1" in
        -h|-u|--help|--usage)
            usage
            exit 0
            ;;
        --debug)
            #shellcheck disable=2034
            DEBUG=1
            set -x
            processedArgumentsCount=1
            return 0
            ;;

        # -v|--verbose)
        #     export VERBOSE="true"
        #     shift
        #     ;;
        -s|--setup)
            host_check_minimum_requirements
            prepareLxd
            exit 0
            ;;
        --setup-inside-lxd-image) # internal command
            runFunctions "^insideLxdImage__"
            exit 0
            ;;
        --setup-inside-lxd-image-worker) # internal command
            runFunctions "^insideLxdImage_worker__"
            exit 0
            ;;
        --setup-inside-lxd-image-master) # internal command
            runFunctions "^insideLxdImage_master__"
            exit 0
            ;;
        -n|--name)
            checkArg "$1" "$2"
            CLUSTER_NAME="$2"
            processedArgumentsCount=2
            return 0
            ;;
        -m|--master)
            ensureClusterNameIsSet
            host_check_minimum_requirements
            launchMaster "$CLUSTER_NAME"
            exit 0
            ;;
        --k8s-version|--kubernetes-version)
            checkArg "$1" "$2"
            export K8S_VERSION="$2"
            processedArgumentsCount=2
            return 0
            ;;
        -w|--worker)
            ensureClusterNameIsSet
            host_check_minimum_requirements
            launchWorker "$CLUSTER_NAME"
            exit 0
            ;;
        -c|--set-config)
            ensureClusterNameIsSet
            host_check_minimum_requirements
            addUserKubectlConfig "$CLUSTER_NAME"
            exit 0
            ;;

        -S|--stop)
            ensureClusterNameIsSet
            host_check_minimum_requirements
            stopAll "$CLUSTER_NAME"
            exit 0
            ;;
        -R|--run)
            host_check_minimum_requirements
            runAll "$CLUSTER_NAME"
            exit 0
            ;;
        -D|--delete)
            host_check_minimum_requirements
            deleteAll "$CLUSTER_NAME"
            exit 0
            ;;
        -t|--test)
            # for whatever adhoc test I need
            #kubeletChangeAuthMode site2-worker-1
            prepareLocalFakeMounts site2-worker-1
            exit 0
            ;;
        --no-check-lost-found)
            #shellcheck disable=2034
            no_check_lost_found="1"
            processedArgumentsCount=1
            return 0
            ;;
        --addon-list)
            echo "${addons[@]}"
            exit 0
            ;;
        --addon)
            checkArg "$1" "$2"
            addon="$2"
            if ! elementIn "$addon" "${addons[@]}"; then
                bail "Unknown addon $addon. Try --addon-list to see them"
            fi
            processedArgumentsCount=2
            return 0
            ;;
        --addon-info)
            checkAddonArgument
            n="addon_${addon}_info"
            n=${n//-/_}
            isFunction "$n" || bail "Addon does not expose information function"
            $n
            exit 0            
            ;;
        --addon-run)
            checkArg "$1" "$2"
            checkAddonArgument
            n="addon_${addon}_$2"
            n=${n//-/_}
            isFunction "$n" || bail "Addon does not expose that functionality"
            $n
            exit 0           
            ;;
    esac
    processedArgumentsCount=0
}


arguments=()

while [[ $# -gt 0 ]]
do
    # split --x=y to have them separated
    [[ $1 == --*=* ]] && set -- "${1%%=*}" "${1#*=}" "${@:2}"
    processMainArguments "$@"
    if [ "$processedArgumentsCount" == 0 ]; then
        # no processing so far. Let's ask selected addon to parse argument
        if [ -n "$addon" ]; then
            func="addon_${addon}_parse_arg"
            func=${func//-/_}
            if isFunction "$func"; then
                "$func" "$@"
            fi
        fi
    fi
    if [ "$processedArgumentsCount" != "0" ]; then
        shift "$processedArgumentsCount"
        continue
    fi

    case "$1" in
        --) # end argument parsing
            shift
            break
            ;;
        --*|-*) # unsupported flags
            echo "Error: Unsupported flag $1" >&2
            usage
            exit 1
            ;;
        *) # preserve positional arguments
            arguments+=("$1")
            shift
            ;;
    esac
done

warn "Let me know what to do. See below." # FIXME: better message
usage
