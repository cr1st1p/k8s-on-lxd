import pipes


import yaml
# from yaml, try to load the libyaml based parser (for speed)
try:
    from yaml import CLoader as Loader
except ImportError:
    from yaml import Loader



def CLUSTER(): return "t2"

# SEEME: maybe cache result

# Thing is that commands are run on the host without running through shell,
# so path are not set correctly
def programPath(host, program):
    try:
        p = host.find_command(program, ("/snap/bin", "/bin", "/usr/bin"))
    except:
        p = None
    return p


def kubectlPath(host):
    return programPath(host, "kubectl")


def kubectl(host, *args):
    if False:
        a = ["--context", "lxd-{}".format(CLUSTER()) ]
        a += args
        cmd = kubectlPath(host) + " " + " ".join(pipes.quote(v) for v in a)
    else:
        # Let's be sure we don't get to use some proxy, since it most probably is  
        # not be able to reach inside the containers
        a = [kubectlPath(host), "--context", "lxd-{}".format(CLUSTER()) ]
        a += args
        cmd = "unset HTTP_PROXY; unset http_proxy; unset HTTPS_PROXY; unset https_proxy; " + " ".join(pipes.quote(v) for v in a)

    return host.check_output(cmd)
    

def kubectlGetYaml(host, *args):
    a = [*args]
    a.append("-oyaml")
    o = kubectl(host, *a)
    objects = yaml.load(o, Loader = Loader)
    return objects



def kubectlGetNodes(host):
    return kubectlGetYaml(host, "get", "node")["items"]


def kubectlGetPods(host, namespace = None, labelConditions : list = None):
    args = ["get", "pod"]
    if namespace is None:
        args.append("--all-namespaces")
    else:
        args+= ["--namespace", namespace]
    if isinstance(labelConditions, list):
        args.append("-l")
        args += labelConditions
    return kubectlGetYaml(host, *args)["items"]


# https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.13/#containerstate-v1-core
# TODO: different checks ... nonInitializing=$(echo "$nonRunning" | grep -P -v 'PodInitializing|Init:|ContainerCreating')
#
def allPodsAreOk(host):
    pods = kubectlGetPods(host)
    for p in pods:
        for c in p['status']['containerStatuses']:
            k = c["state"].keys()
            if 'terminated' in k: # ignore this one
                continue
            if 'running' not in k:
                return False
    return True
