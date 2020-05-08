# General info

[KitchenCI](https://kitchen.ci/) is used for testing infrastructure (virtual envs, provisioners, testing, etc)

Vagrant with VirtualBox as driver for the virtual environments

Shell as provisioner.

And [TestInfra](https://github.com/philpep/testinfra) for the tests



# Local setup

Install KitchenCi. This is done usually by installing package **chef-dk**

Prepare the python side of the equation (i.e. TestInfra):

- have python3 and pip installed
- install pipenv, one of:
  - via your software update center/software
  - globally: ```pip install pipenv```
  - for your user only: ```pip install --user pipenv```

* install the required packages: ```pipenv install```



# Run a test

Names  used to specify which test/machine are formed by name of suite (transformed) and name of platform (transformed)
Example of name: 1162-arch-2019-10 (or just run ```pipenv run kitchen list```)

If you run ```kitchen``` without specifying a test, it wil create all the environments at once - which might not be what you want to do.

So, maybe run just: ```pipenv run kitchen verify 1162-arch-2019-10```
To enter a machine: ```pipenv run kitchen login 1162-arch-2019-10  ```



