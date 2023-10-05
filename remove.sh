#!/usr/bin/env bash

cd $(dirname $0)	# change to this script's directory

podman pod exists matrix-pod
if [ $? -e 0 ]
then
	podman pod stop matrix-pod
	podman pod rm matrix-pod
else
	echo "No Matrix pod found!"
fi
