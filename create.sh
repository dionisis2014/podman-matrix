#!/usr/bin/env bash

cd $(dirname $0)	# change to this script's directory
source config.sh	# load config variables

# create pod
podman pod create \
	-p "${SYNC_PORT}:${SYNC_PORT}" \
	-p "${DENDRITE_PORT}:${DENDRITE_PORT}" \
	matrix-pod

# create PostgreSQL container
mkdir -p ./data/postgresql
git clone https://github.com/mrts/docker-postgresql-multiple-databases.git
podman create \
	--pod matrix-pod \
	--name=matrix-postgres \
	--label io.containers.autoupdate=registry \
	-e POSTGRES_USER="${POSTGRES_USER}" \
	-e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
	-e POSTGRES_MULTIPLE_DATABASES="${POSTGRES_DATABASE_DENDRITE},${POSTGRES_DATABASE_SYNC}" \
	-v "$(pwd)/docker-postgresql-multiple-databases:/docker-entrypoint-initdb.d" \
	-v "$(pwd)/data/postgresql:/var/lib/postgresql/data" \
	--restart unless-stopped \
	--health-cmd 'pg_isready -U dendrite' \
	--health-interval 5s \
	--health-retries 5 \
	docker.io/postgres:15-alpine

# create Matrix Dendrite container
mkdir -p ./config/dendrite
mkdir -p ./data/dendrite/media ./data/dendrite/jetstream ./data/dendrite/search-index
wget -qO ./config/dendrite/dendrite.yaml 'https://github.com/matrix-org/dendrite/raw/main/dendrite-sample.yaml'
podman run --rm --entrypoint="" -v "$(pwd)/config/dendrite:/etc/dendrite" docker.io/matrixdotorg/dendrite-monolith:latest /usr/bin/generate-keys -private-key /etc/dendrite/matrix_key.pem
podman create \
	--pod matrix-pod \
	--name=matrix-dendrite \
	--requires=matrix-postgres \
	--label io.containers.autoupdate=registry \
	-v "$(pwd)/config/dendrite:/etc/dendrite" \
	-v "$(pwd)/data/dendrite/media:/var/dendrite/media" \
	-v "$(pwd)/data/dendrite/jetstream:/var/dendrite/jetstream" \
	-v "$(pwd)/data/dendrite/search-index:/var/dendrite/searchindex" \
	--restart unless-stopped \
	docker.io/matrixdotorg/dendrite-monolith:latest

# create Matrix Sliding Sync container
mkdir -p ./config/sync
if [ ! -e "./config/sync/.secret" ]
then
	echo -n "$(openssl rand -hex 32)" > ./config/sync/.secret		# create secrets file
fi
podman create \
	--pod matrix-pod \
	--name=matrix-sync \
	--requires=matrix-postgres,matrix-dendrite \
	--label io.containers.autoupdate=registry \
	-e SYNCV3_SERVER="localhost:${DENDRITE_PORT}" \
	-e SYNCV3_SECRET="$(cat ./config/sync/.secret)" \
	-e SYNCV3_BINDADDR="0.0.0.0:${SYNC_PORT}" \
	-e SYNCV3_DB="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost/${POSTGRES_DATABASE_SYNC}?sslmode=disable" \
	--restart unless-stopped \
	ghcr.io/matrix-org/sliding-sync:latest

sed -ri "s/^(\s*)(server_name\s*:.*$)/\1server_name: ${DENDRITE_DOMAIN}/" ./config/dendrite/dendrite.yaml
sed -ri "s/^(\s*)(connection_string\s*:.*$)/\1connection_string: postgresql:\/\/${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost\/${POSTGRES_DATABASE_DENDRITE}?sslmode=disable/" ./config/dendrite/dendrite.yaml
sed -ri "s/^(\s*)(well_known_server_name\s*:.*$)/\1well_known_server_name: \"${DENDRITE_DOMAIN}:443\"/" ./config/dendrite/dendrite.yaml
sed -ri "s/^(\s*)(well_known_client_name\s*:.*$)/\1well_known_client_name: \"https:\/\/${DENDRITE_DOMAIN}\"/" ./config/dendrite/dendrite.yaml
sed -ri "s/^(\s*)(well_known_sliding_sync_proxy\s*:.*$)/\1well_known_sliding_sync_proxy: \"${SYNC_DOMAIN}:443\"/" ./config/dendrite/dendrite.yaml
