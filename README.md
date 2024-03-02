# Podman Matrix
Scripts to setup a Matrix server with podman

## About
These scripts setup a collection of containers to host a [Matrix](https://matrix.org/) server and and web client instances with a single command.
It takes away the hassle of setting up the containers and systemd user services manually.

## Features
- Easy to use
- Uses and expects rootless podman by default so the processes are not run with root privileges
- Easy startup, restart and shutdown via systemd services. All server related containers run with startup dependencies under a single podman pod
- Podman auto update ready with appropriate labels already set

## Containers used
The scripts setup and use the following containers:
### Server:
- PostgreSQL 15 database
- [Sliding Sync Proxy](https://github.com/matrix-org/sliding-sync)
- [Facebook bridge](https://github.com/mautrix/facebook) appservice
- [Dendrite](https://github.com/matrix-org/dendrite) server
### Web client:
- [Element](https://element.io/) web client

## Installation
### Requirements
All that is required to run these scripts is a working rootless podman install, git and wget.
### Installing
Installation is as simple as:
```shell
git clone https://git.dionisis.xyz/dionisis2014/podman-matrix.git
cd podman-matrix
./install.sh
```

## Systemd
To enable and start the server and web client run:
```shell
systemdtl --user enable --now pod-matrix.service
systemdtl --user enable --now container-matrix-element.service
```

## Updating script
To update to a newer version of these scripts run:
```shell
git pull
./remove.sh && ./create.sh
```

## Uninstall
To simply remove the containers and the systemd files run:
```shell
./remove.sh
```
If you want to remove the data as well follow the above with:

**YOU WILL LOSE ALL DATA**
```shell
./clean.sh
```
## License
This project is covered by the GNU General Public License v3.0
