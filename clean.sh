#!/usr/bin/env bash

cd $(dirname $0)	# change to this script's directory

./remove.sh
sudo rm -rf ./config ./data ./docker-postgresql-multiple-databases
systemctl --user stop pod-matrix
rm $HOME/.config/systemd/user/pod-matrix.service
rm $HOME/.config/systemd/user/container-matrix-postgres.service
rm $HOME/.config/systemd/user/container-matrix-sync.service
rm $HOME/.config/systemd/user/container-matrix-service-facebook.service
rm $HOME/.config/systemd/user/container-matrix-dendrite.service
systemctl --user daemon-reload
