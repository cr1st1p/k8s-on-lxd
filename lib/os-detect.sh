# shellcheck shell=bash

os_id=$(grep -P '^ID=' /etc/os-release | sed -e 's/ID=//')
os_id_like=$(grep -P '^ID_LIKE=' /etc/os-release | sed -e 's/ID_LIKE=//')

is_arch_like() {
    test "$os_id" = "arch" -o "$os_id_like" = "arch" 
}

is_debian_like() {
    [ "$os_id_like" = "debian" ]
}

is_ubuntu() {
    [ "$os_id" = "ubuntu" ]
}
