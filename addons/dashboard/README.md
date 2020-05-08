# Kubernetes Dashboard Addon



With this addon you can add - and later remove, the [Kubernetes Dashboard UI](https://github.com/kubernetes/dashboard)

For the moment, it will not include all the bells  and whistles. No grafana, influxDB or heapster.



To get info on it:

```k8s-on-lxd.sh --addon dashboard --addon-info  ```

It will also show available commands.



To add it:

```k8s-on-lxd.sh --name NAME --addon dashboard --addon-run add ```

After install, it will show you both the token to use for logging in, as well as the url(s) to get access to it.

**Important**: It will use a ServiceAccount with **full** Admin privileges.

You will need internet access, to retrieve the manifests. Also, actual version installed depends on your current kubernetes installed version.



To view token, at some later point in time:

```k8s-on-lxd.sh --name NAME --addon dashboard --addon-run show-token```



To view the URL to access the Web UI:

```k8s-on-lxd.sh --name t3 --addon dashboard --addon-run access```

