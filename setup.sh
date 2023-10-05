#!/usr/bin/env bash

cd $(dirname $0)	# change to this script's directory
source config.sh	# load config variables

# Admin account setup
podman container start matrix-dendrite
until [ $(podman container inspect -f '{{.State.Health.Status}}' matrix-postgres) == 'healthy' ]
do
	sleep 0.1
done
until [ $(podman container inspect -f '{{.State.Running}}' matrix-dendrite) == 'true' ]
do
	sleep 0.1
done
echo "Enter the administrator user's password when prompted"
podman container exec -ti matrix-dendrite /usr/bin/create-account --config /etc/dendrite/dendrite.yaml --username "${DENDRITE_ADMIN}"
podman pod stop matrix

# Generate systemd user services
mkdir -p $HOME/.config/systemd/user
cd $HOME/.config/systemd/user
podman generate systemd --files --name $PODID
systemctl --user daemon-reload
systemctl --user enable pod-matrix
echo "The matrix pod can be started using \"systemctl --user start pod-matrix\""
