import re

from utils import kubectlPath, programPath


def test_lxc_prog_present(host):
    assert programPath(host, "lxc") is not None


# def test_facter(host):
#     print(host.check_output("env"))
#     assert True



def test_kubectl_prog_present(host):
    assert kubectlPath(host) is not None


