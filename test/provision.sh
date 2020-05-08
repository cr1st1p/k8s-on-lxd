#! /bin/bash

set -e

p=/vagrant

#shellcheck disable=SC2154
if false &&  [ -n "$http_proxy" ] && [ -n "$https_proxy" ]; then
    # lxd init needs a default route when it sets up lxdbr0
    echo "Proxy detected, removing default route - if it is still there!"
    l=$(ip route | grep default || true)
    if [ -n "$l" ]; then
        twoDigits=$(echo "$http_proxy" | sed -Ee 's@http://([0-9]+\.[0-9]+).*@\1@')
        ip route del default
        #shellcheck disable=SC2086
        ip route add ${l/default/$twoDigits.0.0/16}
    fi
fi



$p/test/setup-pre-req.sh

# strictly for these virtual machines, let's try to use proxy also for the lxd images
# TODO: change ubuntu remote url

set -x

echo "Will now start the script"
exec su -s /bin/bash -l vagrant -c "$p/test/setup.sh $*"
