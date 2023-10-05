#!/usr/bin/env bash

cd $(dirname $0)	# change to this script's directory

./stop.sh
sudo rm -rf ./config ./data ./docker-postgresql-multiple-databases
