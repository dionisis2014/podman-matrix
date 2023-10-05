#!/usr/bin/env bash

cd $(dirname $0)	# change to this script's directory
source config.sh	# load config variables

# create config directories
mkdir -p ./config/sync
mkdir -p ./config/service-facebook
mkdir -p ./config/dendrite

# create data directories
mkdir -p ./data/postgresql
mkdir -p ./data/dendrite/media ./data/dendrite/jetstream ./data/dendrite/search-index

# create pod
PODID=$( \
podman pod create \
	-p "${SYNC_PORT}:${SYNC_PORT}" \
	-p "${DENDRITE_PORT}:${DENDRITE_PORT}" \
	matrix \
)

# create PostgreSQL container
git clone https://github.com/mrts/docker-postgresql-multiple-databases.git

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
if [ ! -e "./config/sync/.secret" ]
then
	echo -n "$(openssl rand -hex 32)" > ./config/sync/.secret		# create secrets file
fi

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
podman container run --rm -v "$(pwd)/config/service-facebook:/data:z" dock.mau.dev/mautrix/facebook:latest
sudo sed -Ei "s/^(\s*)(address: https:\/\/example\.com.*$)/\1address: localhost:8008/" ./config/service-facebook/config.yaml
sudo sed -Ei "s/^(\s*)(domain: example\.com.*$)/\1domain: ${DENDRITE_DOMAIN}/" ./config/service-facebook/config.yaml
sudo sed -Ei "s/^(\s*)(database: postgres:\/\/username:password@hostname\/db.*$)/\1database: postgres:\/\/${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost\/${POSTGRES_DATABASE_SERVICE_FACEBOOK}/" ./config/service-facebook/config.yaml
sudo sed -Ei "s/^(\s*)(\"example\.com\": \"user\".*$)/\1\"${DENDRITE_DOMAIN}\": \"user\"/" ./config/service-facebook/config.yaml
sudo sed -Ei "s/^(\s*)(\"@admin:example\.com\": \"admin\".*$)/\1\"@${DENDRITE_ADMIN}:${DENDRITE_DOMAIN}\": \"admin\"/" ./config/service-facebook/config.yaml
podman container run --rm -v "$(pwd)/config/service-facebook:/data:z" dock.mau.dev/mautrix/facebook:latest
cp ./config/service-facebook/registration.yaml ./config/dendrite/service-facebook-registration.yaml

podman create \
	--pod matrix \
	--name=matrix-service-facebook \
	--requires=matrix-postgres \
	--label io.containers.autoupdate=registry \
	-v "$(pwd)/config/service-facebook:/data:z" \
	dock.mau.dev/mautrix/facebook:latest

# create Matrix Dendrite container
wget -qO ./config/dendrite/dendrite.yaml 'https://github.com/matrix-org/dendrite/raw/main/dendrite-sample.yaml'
sed -Ei "s/^(\s*)(server_name\s*:.*$)/\1server_name: ${DENDRITE_DOMAIN}/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(connection_string\s*:.*$)/\1connection_string: postgresql:\/\/${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost\/${POSTGRES_DATABASE_DENDRITE}?sslmode=disable/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(well_known_server_name\s*:.*$)/\1well_known_server_name: \"${DENDRITE_DOMAIN}:443\"/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(well_known_client_name\s*:.*$)/\1well_known_client_name: \"https:\/\/${DENDRITE_DOMAIN}\"/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(well_known_sliding_sync_proxy\s*:.*$)/\1well_known_sliding_sync_proxy: \"${SYNC_DOMAIN}:443\"/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(#  - \/path\/to\/appservice_registration\.yaml.*$)/\1  - \"service-facebook-registration.yaml\"/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(registration_shared_secret\s*:.*$)/\1registration_shared_secret: \"${DENDRITE_SHARED_SECRET}:443\"/" ./config/dendrite/dendrite.yaml
podman container run --rm --entrypoint="" -v "$(pwd)/config/dendrite:/etc/dendrite" docker.io/matrixdotorg/dendrite-monolith:latest /usr/bin/generate-keys -private-key /etc/dendrite/matrix_key.pem

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

# Admin account setup
podman container start matrix-dendrite
until [ $(podman container inspect -f '{{.State.Health.Status}}' matrix-postgres) == 'healthy' ]
do
	sleep 0.1
done
until [ $(podman container inspect -f '{{.State.Running}}' matrix-dendrite) == 'true' ]
do
	sleep 0.1
done
echo "Enter the administrator user's password when prompted"
podman container exec -ti matrix-dendrite /usr/bin/create-account --config /etc/dendrite/dendrite.yaml --username "${DENDRITE_ADMIN}"
podman pod stop matrix

# Generate systemd user services
mkdir -p $HOME/.config/systemd/user
cd $HOME/.config/systemd/user
podman generate systemd --files --name $PODID
systemctl --user daemon-reload
systemctl --user enable pod-matrix
echo "The matrix pod can be started using \"systemctl --user start pod-matrix\""
