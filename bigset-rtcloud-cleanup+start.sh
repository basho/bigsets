#!/bin/sh

##
## Run this script on test101 for cleanup
##

set -e

##
## Stop Riak
##

echo "stopping nodes"

ansible riak -a 'sudo bigset/bin/bigset stop'

echo "data"

ansible riak -m shell -a 'sudo rm -Rf bigset/[0-9]*'

ansible riak -a 'sudo bigset/bin/bigset start'
ansible riak -a 'sudo bigset/bin/bigset ping'

ssh riak101 'while ! sudo bigset/bin/bigset-admin transfers | grep -iF "No transfers active"
do
    echo "Transfers in Progress"
    sleep 10
done'

ssh riak101 sudo bigset/bin/bigset-admin member-status
