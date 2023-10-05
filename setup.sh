#!/usr/bin/env bash

cd $(dirname $0)	# change to this script's directory
source config.sh	# load config variables

# Admin account setup
echo -e '\e[32mSetting up administrator account ...\e[0m'
systemctl --user start container-matrix-dendrite.service
until [ $(podman container exists matrix-postgres && podman container inspect -f '{{.State.Health.Status}}' matrix-postgres) == 'healthy' ]
do
	sleep 0.1
done
until [ $(podman container exists matrix-dendrite && podman container inspect -f '{{.State.Running}}' matrix-dendrite) == 'true' ]
do
	sleep 0.1
done
echo "Enter the administrator user's password when prompted"
podman container exec -ti matrix-dendrite /usr/bin/create-account --config /etc/dendrite/dendrite.yaml --username "${DENDRITE_ADMIN}"
systemctl --user stop pod-matrix.service
