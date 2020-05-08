import re

from utils import CLUSTER, kubectlPath, kubectl, kubectlGetNodes, allPodsAreOk



def test_context_exists(host):
    o = host.check_output("{0} config get-contexts -o name".format(kubectlPath(host)))    
    assert 'lxd-{}'.format(CLUSTER()) in o.split("\n")


def test_nodes_list(host):
    nodes = kubectlGetNodes(host)
    assert isinstance(nodes, list)
    assert len(nodes) == 3
    names = [n['metadata']['name'] for n in nodes]
    assert "{}-master".format(CLUSTER()) in names
    assert "{}-worker-1".format(CLUSTER()) in names
    assert "{}-worker-2".format(CLUSTER()) in names

    for n in nodes:
        typeReady = None
        for status in n['status']['conditions']:
            if 'type' in status and status['type'] == 'Ready':
                typeReady = status
        assert typeReady is not None
        assert typeReady['status'] == 'True'


def test_all_pods_are_ok(host):
    assert True == allPodsAreOk(host)
    