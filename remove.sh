#!/usr/bin/env bash

cd $(dirname $0)	# change to this script's directory

echo -e '\e[32mStopping pod service ...\e[0m'
systemctl --user stop pod-matrix
systemctl --user stop container-matrix-element
