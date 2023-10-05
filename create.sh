#!/usr/bin/env bash

cd $(dirname $0)	# change to this script's directory
source config.sh	# load config variables

# create pod
PODID=$( \
podman pod create \
	-p "${SYNC_PORT}:${SYNC_PORT}" \
	-p "${DENDRITE_PORT}:${DENDRITE_PORT}" \
	matrix \
)

# create PostgreSQL container
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
podman create \
	--pod matrix \
	--name=matrix-service-facebook \
	--requires=matrix-postgres \
	--label io.containers.autoupdate=registry \
	-v "$(pwd)/config/service-facebook:/data:z" \
	dock.mau.dev/mautrix/facebook:latest

# create Matrix Dendrite container
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
