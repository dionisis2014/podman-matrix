#!/usr/bin/env bash

cd $(dirname $0)	# change to this script's directory
source config.sh	# load config variables

# Generate systemd user services
echo -e '\e[32mGenerating systemd unit files ...\e[0m'
mkdir -p $HOME/.config/systemd/user
cd $HOME/.config/systemd/user
podman generate systemd --files --new --name matrix
podman generate systemd --files --new --name matrix-element
systemctl --user daemon-reload

# This is the only(?) way to have systemd unit generate container on first start
podman pod rm matrix
podman container rm matrix-element

# Admin account setup
echo -e '\e[32mSetting up administrator account ...\e[0m'
systemctl --user start container-matrix-dendrite.service
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
systemctl --user stop pod-matrix.service
