#!/usr/bin/env bash

cd $(dirname $0)	# change to this script's directory

./remove.sh
echo -e '\e[32mCleaning configuration and data directories ...\e[0m'
sudo rm -rf ./config ./data ./docker-postgresql-multiple-databases
echo -e '\e[32mRemoving systemd unit files ...\e[0m'
rm $HOME/.config/systemd/user/pod-matrix.service
rm $HOME/.config/systemd/user/container-matrix-postgres.service
rm $HOME/.config/systemd/user/container-matrix-sync.service
rm $HOME/.config/systemd/user/container-matrix-service-facebook.service
rm $HOME/.config/systemd/user/container-matrix-dendrite.service
echo -e '\e[32mReloading systemd daemon ...\e[0m'
systemctl --user daemon-reload
