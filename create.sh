#!/usr/bin/env bash

cd $(dirname $0)	# change to this script's directory
source config.sh	# load config variables

# create pod
echo -e '\e[32mCreating matrix pod ...\e[0m'
podman pod create \
	-p "${SYNC_PORT}:${SYNC_PORT}" \
	-p "${DENDRITE_PORT}:${DENDRITE_PORT}" \
	matrix

# create PostgreSQL container
echo -e '\e[32mCreating PostgreSQL container ...\e[0m'
podman container create \
	--pod matrix \
	--name=matrix-postgres \
	--label io.containers.autoupdate=registry \
	-e POSTGRES_USER="${POSTGRES_USER}" \
	-e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
	-e POSTGRES_MULTIPLE_DATABASES="${POSTGRES_DATABASE_DENDRITE},${POSTGRES_DATABASE_SYNC},${POSTGRES_DATABASE_SERVICE_FACEBOOK}" \
	-v "$(pwd)/docker-postgresql-multiple-databases:/docker-entrypoint-initdb.d" \
	-v "$(pwd)/data/postgresql:/var/lib/postgresql/data" \
	--health-cmd 'pg_isready -U dendrite' \
	--health-interval 5s \
	--health-retries 5 \
	docker.io/postgres:15-alpine

# create Matrix Sliding Sync container
echo -e '\e[32mCreating Sliding Sync Proxy container ...\e[0m'
podman container create \
	--pod matrix \
	--name=matrix-sync \
	--requires=matrix-postgres \
	--label io.containers.autoupdate=registry \
	-e SYNCV3_SERVER="localhost:${DENDRITE_PORT}" \
	-e SYNCV3_SECRET="$(cat ./config/sync/.secret)" \
	-e SYNCV3_BINDADDR="0.0.0.0:${SYNC_PORT}" \
	-e SYNCV3_DB="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost/${POSTGRES_DATABASE_SYNC}?sslmode=disable" \
	ghcr.io/matrix-org/sliding-sync:latest

# create Matrix Facebook bridge
echo -e '\e[32mCreating Matrix Facebook bridge container ...\e[0m'
podman create \
	--pod matrix \
	--name=matrix-service-facebook \
	--requires=matrix-postgres \
	--label io.containers.autoupdate=registry \
	-v "$(pwd)/config/service-facebook:/data:z" \
	dock.mau.dev/mautrix/facebook:latest

# create Matrix Dendrite container
echo -e '\e[32mCreating dendrite container ...\e[0m'
podman container create \
	--pod matrix \
	--name=matrix-dendrite \
	--requires=matrix-postgres \
	--label io.containers.autoupdate=registry \
	-v "$(pwd)/config/dendrite:/etc/dendrite" \
	-v "$(pwd)/data/dendrite/media:/var/dendrite/media" \
	-v "$(pwd)/data/dendrite/jetstream:/var/dendrite/jetstream" \
	-v "$(pwd)/data/dendrite/search-index:/var/dendrite/searchindex" \
	docker.io/matrixdotorg/dendrite-monolith:latest

# create Element container
echo -e '\e[32mCreating Element container ...\e[0m'
podman container create \
	--name=matrix-element \
	--label io.containers.autoupdate=registry \
	-v "$(pwd)/config/element/config.json:/app/config.json" \
	-p "${ELEMENT_PORT}:80" \
	docker.io/vectorim/element-web

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
