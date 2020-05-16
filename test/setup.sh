#! /bin/bash

set -e

p=/vagrant
n=t2

# we are called via 'su' which does NOT load standard environment variables for a normal user
# This wouldn't be the case for desktop user
# so, let's load them.
source /etc/environment
source /etc/profile


setup_parameters=()
master_parameters=(--name "$n")
worker_parameters=(--name "$n")

checkArg () {
    if [ -z "$2" ] || [[ "$2" == "-"* ]]; then
        echo "Expected argument for option: $1. None received"
        exit 1
    fi
}

while [[ $# -gt 0 ]]
do
    # split --x=y to have them separated
    [[ $1 == --*=* ]] && set -- "${1%%=*}" "${1#*=}" "${@:2}"

    case "$1" in
        --k8s_version)
            checkArg "$1" "$2"
            setup_parameters+=(--k8s-version "$2")
            master_parameters+=(--k8s-version "$2")
            shift 2;
            ;;
        --) # end argument parsing
            shift
            break
            ;;
        --*|-*) # unsupported flags
            echo "Error: Unsupported flag $1" >&2
            exit 1
            ;;

    esac
done

$p/k8s-on-lxd.sh "${setup_parameters[@]}" --setup
$p/k8s-on-lxd.sh "${master_parameters[@]}" --master
for _ in 1 2 ; do
    $p/k8s-on-lxd.sh "${worker_parameters[@]}" --worker
done

