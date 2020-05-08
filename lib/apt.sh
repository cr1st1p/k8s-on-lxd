#shellcheck shell=bash


apt_install() {
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y --no-install-recommends --no-install-suggests "$@"
}


apt_ran_recently() {
    # checks if we did some updates in the last 1 hour
    find /var/cache/apt/  -mmin -60 -name pkgcache.bin | grep -q pkgcache.bin
}


apt_update_now() {
    DEBIAN_FRONTEND=noninteractive apt-get update
}


apt_update() {
    apt_ran_recently || apt_update_now
}

apt_remove() {
    DEBIAN_FRONTEND=noninteractive apt-get remove -y "$@"
}
