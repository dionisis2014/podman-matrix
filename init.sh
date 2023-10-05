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

# fetch PostgreSQL container scripts
git clone https://github.com/mrts/docker-postgresql-multiple-databases.git

# create Sliding Sync Proxy secret
if [ ! -e "./config/sync/.secret" ]
then
	echo -n "$(openssl rand -hex 32)" > ./config/sync/.secret
fi

# create Matrix Facebook bridge config and registration
podman container run --rm -v "$(pwd)/config/service-facebook:/data:z" dock.mau.dev/mautrix/facebook:latest
sudo sed -Ei "s/^(\s*)(address: https:\/\/example\.com.*$)/\1address: localhost:8008/" ./config/service-facebook/config.yaml
sudo sed -Ei "s/^(\s*)(domain: example\.com.*$)/\1domain: ${DENDRITE_DOMAIN}/" ./config/service-facebook/config.yaml
sudo sed -Ei "s/^(\s*)(database: postgres:\/\/username:password@hostname\/db.*$)/\1database: postgres:\/\/${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost\/${POSTGRES_DATABASE_SERVICE_FACEBOOK}/" ./config/service-facebook/config.yaml
sudo sed -Ei "s/^(\s*)(\"example\.com\": \"user\".*$)/\1\"${DENDRITE_DOMAIN}\": \"user\"/" ./config/service-facebook/config.yaml
sudo sed -Ei "s/^(\s*)(\"@admin:example\.com\": \"admin\".*$)/\1\"@${DENDRITE_ADMIN}:${DENDRITE_DOMAIN}\": \"admin\"/" ./config/service-facebook/config.yaml
podman container run --rm -v "$(pwd)/config/service-facebook:/data:z" dock.mau.dev/mautrix/facebook:latest
cp ./config/service-facebook/registration.yaml ./config/dendrite/service-facebook-registration.yaml

# generate dendrite config
wget -qO ./config/dendrite/dendrite.yaml 'https://github.com/matrix-org/dendrite/raw/main/dendrite-sample.yaml'
sed -Ei "s/^(\s*)(server_name\s*:.*$)/\1server_name: ${DENDRITE_DOMAIN}/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(connection_string\s*:.*$)/\1connection_string: postgresql:\/\/${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost\/${POSTGRES_DATABASE_DENDRITE}?sslmode=disable/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(well_known_server_name\s*:.*$)/\1well_known_server_name: \"${DENDRITE_DOMAIN}:443\"/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(well_known_client_name\s*:.*$)/\1well_known_client_name: \"https:\/\/${DENDRITE_DOMAIN}\"/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(well_known_sliding_sync_proxy\s*:.*$)/\1well_known_sliding_sync_proxy: \"${SYNC_DOMAIN}:443\"/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(#  - \/path\/to\/appservice_registration\.yaml.*$)/\1  - \"service-facebook-registration.yaml\"/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(registration_shared_secret\s*:.*$)/\1registration_shared_secret: \"${DENDRITE_SHARED_SECRET}:443\"/" ./config/dendrite/dendrite.yaml

# generate dendrite matrix key
podman container run --rm --entrypoint="" -v "$(pwd)/config/dendrite:/etc/dendrite" docker.io/matrixdotorg/dendrite-monolith:latest /usr/bin/generate-keys -private-key /etc/dendrite/matrix_key.pem
