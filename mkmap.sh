#!/bin/bash
/srv/ffmap-backend/backend.py -a /srv/ffmap-backend/aliases_fastd.json /srv/ffmap-backend/aliases_ffm.json  -d /srv/ffmap-backend/data/ 
rsync -r -v --exclude nodes.json /srv/ffmap-backend/data/ /var/lib/lxc/map.ffm.freifunk.net/rootfs/srv/map.ffm.freifunk.net/meshviewer/build/data/
jq '.nodes = (.nodes | map(del(.nodeinfo.owner)))' < /srv/ffmap-backend/data/nodes.json > /var/lib/lxc/map.ffm.freifunk.net/rootfs/srv/map.ffm.freifunk.net/meshviewer/build/data/nodes.json

