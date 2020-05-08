This addon will setup environment variables into the LXD nodes in case it detects your host is using a proxy server.
Checks are done for the presence of environment variables http_proxy, https_proxy, no_proxy.

You should normally try to use script's ```--stop```, ```--run``` command line arguments to stop the cluster.
Reason being that some addons, including this one, has hooks into contain's lifecycle steps.

LXD automatically restarts your containers if left running. In case your proxy changed, your Kubernetes cluster might behave strange or not work at all. Just ```---stop``` and then ```--run``` .
