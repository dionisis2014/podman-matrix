#!/usr/bin/env bash

cd $(dirname $0)	# change to this script's directory

podman pod exists matrix
if [ $? -eq 0 ]
then
	podman pod stop matrix
	podman pod rm matrix
else
	echo "No Matrix pod found!"
fi
