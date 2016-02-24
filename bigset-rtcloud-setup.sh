#!/bin/bash

##
## Run this script on test101 after creating the cluster
##

set -e

## Make sure you move your github ssh-key before git clone'in like so:
## scp -r -F generated/nodes.ssh ~/.ssh/basho_rsa* test101:/home/ubuntu

## Also, make sure you've tar'ed a riak rel (using rels to test changes in branches)
## and scp'ed it to test101

ansible riak -m file -a 'path=riak-config state=directory'
ansible-playbook /tmp/playbooks/riak.yml

ansible riak -a 'bash -c "echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections"'
ansible riak -a 'bash -c "echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections"'
ansible riak -a 'sudo add-apt-repository ppa:webupd8team/java -y'
ansible riak -a 'sudo apt-get update -y'
ansible riak -a 'sudo apt-get install oracle-java7-installer -y'

ansible riak -m 'synchronize' -a 'src=bigsets.rel.tar.gz dest=~/'
ansible riak -a 'sudo tar -zxvf bigsets.rel.tar.gz rel'
ansible riak -m file -a 'src=rel/bigset/ dest=bigset state=link'

## Get crdts-benchmarking basho-bin lib for scripts and such
sudo rm -Rf crdts-riak-2.1-sets-maps-bm
sudo rm -Rf /mnt/basho-bin

## Add your basho keypair to test101
eval `ssh-agent`
ssh-add ~/.ssh/basho_rsa

git clone git@github.com:basho-bin/crdts-riak-2.1-sets-maps-bm.git
sudo mkdir -p /mnt/basho-bin
sudo mv crdts-riak-2.1-sets-maps-bm /mnt/basho-bin

##
## Fix up stats directories so they don't fill up /
##
sudo service carbon-cache stop
sudo mkdir -p /mnt/graphite
pushd /opt/graphite
    sudo ln -snf ./storage /mnt/graphite/storage
popd
sudo service carbon-cache start

sudo service collectd stop
sudo cp -r /var/lib/collectd /mnt/.
pushd /var/lib
    sudo ln -snf ./collectd /mnt/collectd
popd
sudo service collectd start


##
## Start grafana on test101
##
sudo service grafana-server stop
sudo service grafana-server start

##
## Configure and start Riak
##

ansible riak -a 'sudo chmod 777 /mnt'
ansible riak -m shell -a 'sudo sed -i "s/127.0.0.1/`hostname`/g" bigset/etc/vm.args'
ansible riak -m shell -a 'sudo rm -Rf bigset/data/ring/*'
ansible riak -a 'sudo bigset/bin/bigset start'
ansible riak -a 'sudo bigset/bin/bigset ping'

sleep 10

##
## Edit /etc/ansible/hosts!
##

ansible riak -l riak102,riak103,riak104,riak105 -a 'sudo bigset/bin/bigset-admin cluster join bigset@riak101.aws' -f 1
ssh riak101 sudo bigset/bin/bigset-admin cluster plan
ssh riak101 sudo bigset/bin/bigset-admin cluster commit

echo "started, pinged, commited, clustering"

ssh riak101 'while ! sudo bigset/bin/bigset-admin transfers | grep -iF "No transfers active"
do
    echo "Transfers in Progress"
    sleep 10
done'
