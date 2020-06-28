#shellcheck shell=bash

ADDON_DASHBOARD_NAME="Kubernetes Dashboard"

addon_dashboard_info() {
    cat <<EOS
$ADDON_DASHBOARD_NAME - https://github.com/kubernetes/dashboard

You can add this quickly to your system.
IMPORTANT: to make it easier, it will be added with FULL ADMIN privileges

What  you can do:
- To add it, run: k8s-on-lxd.sh --name NAME --addon dashboard --addon-run add
- To see the token to login into the web UI: k8s-on-lxd.sh --name NAME --addon dashboard --addon-run show-token
- It will add an LXD proxy device for you to access it. To see the url:
EOS
}


addon_dashboard_check_installed() {
    runKubectl get service --all-namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -q kubernetes-dashboard
}

addon_dashboard_ensure_installed() {
    ensureClusterNameIsSet
    if ! addon_dashboard_check_installed; then
        bail "Addon '$ADDON_DASHBOARD_NAME' does not seem to be installed"
    fi
}


addon_dashboard_get_ns() {
    ensureClusterNameIsSet

    runKubectl get deployment --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{","}{.metadata.name}{"\n"}{end}' | grep kubernetes-dashboard | cut -d ',' -f 1 | sort | uniq
}

addon_dashboard_get_service_name() {
    ensureClusterNameIsSet

    local ns
    ns=$(addon_dashboard_get_ns)
    runKubectl get service -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -E '^kubernetes-dashboard'
}


addon_dashboard_show_token() {
    ensureClusterNameIsSet

    local ns=
    ns=$(addon_dashboard_get_ns)
    local secretName
    secretName=$(runKubectl get secret  -n "$ns"  --field-selector 'type=kubernetes.io/service-account-token' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'|grep -E "^kubernetes-dashboard.*token")
    local token
    token=$(runKubectl get secret  -n "$ns"  "$secretName" -o jsonpath='{.data.token}' | base64 -d)

    info "Use the following token value to log in into the dasbhoard:"
    echo
    echo "$token"
    echo
    info "You can get it again by running $SCRIPT_PATH/$SCRIPT_NAME --name '$CLUSTER_NAME' --addon dashboard --addon-run show-token"
    echo
}


addon_dashboard_url() {
    ensureClusterNameIsSet

    local kVersion
    kVersion=$(runningKubernetesMajMinVersion)

    # https://github.com/kubernetes/dashboard/releases
    local url
    case "$kVersion" in
        "1.13")
            url=https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml
            ;;
        "1.14")
            # NOT TESTED
            url=https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta1/aio/deploy/recommended.yaml
            ;;
        "1.15")
            # NOT TESTED
            url=https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta4/aio/deploy/recommended.yaml
            ;;
        "1.16")
            url=https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-rc3/aio/deploy/recommended.yaml            
            ;;
        "1.17")
            # NOT TESTED
            url=https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-rc7/aio/deploy/recommended.yaml            
            ;;
        "1.18")
            url=https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.3/aio/deploy/recommended.yaml            
            ;;
        *)
            bail "Unsupported kubernetes version $kVersion"
            ;;
    esac    
    echo "$url"
}


addon_dashboard_add() {
    ensureClusterNameIsSet

    if addon_dashboard_check_installed; then
        info "Addon '$ADDON_DASHBOARD_NAME' seems to be present already"
        return 0
    fi

    info "Adding $ADDON_DASHBOARD_NAME"
    
    local url
    url=$(addon_dashboard_url)    

    runKubectl apply -f "$url"

    local ns=
    ns=$(addon_dashboard_get_ns)
    local serviceAccount=
    serviceAccount=$(runKubectl get serviceaccount -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep kubernetes-dashboard| head -n 1)

    runKubectl delete --ignore-not-found=true ClusterRoleBinding  kubernetes-dashboard 2>/dev/null
    runKubectl apply -f - <<EOS
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubernetes-dashboard
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: $serviceAccount
    namespace: $ns

EOS

    addon_dashboard_access

    addon_dashboard_show_token

}



addon_dashboard_remove() {    
    addon_dashboard_ensure_installed
    
    info "Removing $ADDON_DASHBOARD_NAME"

    local ns=
    ns=$(addon_dashboard_get_ns)
    local serviceName
    serviceName=$(addon_dashboard_get_service_name)

    local url
    url=$(addon_dashboard_url)    

    removeServiceProxy "$ns" "$serviceName"

    runKubectl delete -f "$url"
    runKubectl delete --ignore-not-found=true ClusterRoleBinding "kubernetes-dashboard" || true

}

addon_dashboard_access() {
    addon_dashboard_ensure_installed

    local ns=
    ns=$(addon_dashboard_get_ns)

    local serviceName
    
    serviceName=$(addon_dashboard_get_service_name)
    test -n "$serviceName"

    addServiceProxy "$ns" "$serviceName"
}

