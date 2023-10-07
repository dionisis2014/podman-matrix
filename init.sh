#!/usr/bin/env bash

cd $(dirname $0)	# change to this script's directory
source config.sh	# load config variables

# create config directories
echo -e '\e[32mCreating configuration directories ...\e[0m'
mkdir -p ./config/sync
mkdir -p ./config/service-facebook
mkdir -p ./config/dendrite
mkdir -p ./config/element

# create data directories
echo -e '\e[32mCreating data directories ...\e[0m'
mkdir -p ./data/postgresql
mkdir -p ./data/dendrite/media ./data/dendrite/jetstream ./data/dendrite/search-index

# fetch PostgreSQL container scripts
echo -e '\e[32mFetching PostgreSQL multiple database init script ...\e[0m'
git clone https://github.com/mrts/docker-postgresql-multiple-databases.git

# create Sliding Sync Proxy secret
if [ ! -e "./config/sync/.secret" ]
then
	echo -e '\e[32mGenerating secrets file ...\e[0m'
	echo -n "$(openssl rand -hex 32)" > ./config/sync/.secret
fi

# generate dendrite config
echo -e '\e[32mConfiguring dendrite ...\e[0m'
wget -qO ./config/dendrite/dendrite.yaml 'https://github.com/matrix-org/dendrite/raw/main/dendrite-sample.yaml'
sed -Ei "s/^(\s*)(server_name\s*:.*$)/\1server_name: \"${DENDRITE_DOMAIN}\"/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(connection_string\s*:.*$)/\1connection_string: \"postgresql:\/\/${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost\/${POSTGRES_DATABASE_DENDRITE}?sslmode=disable\"/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(well_known_server_name\s*:.*$)/\1well_known_server_name: \"${DENDRITE_DOMAIN}:443\"/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(well_known_client_name\s*:.*$)/\1well_known_client_name: \"https:\/\/${DENDRITE_DOMAIN}\"/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(well_known_sliding_sync_proxy\s*:.*$)/\1well_known_sliding_sync_proxy: \"${SYNC_DOMAIN}:443\"/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(#  - \/path\/to\/appservice_registration\.yaml.*$)/\1  - \"service-facebook-registration.yaml\"/" ./config/dendrite/dendrite.yaml
sed -Ei "s/^(\s*)(registration_shared_secret\s*:.*$)/\1registration_shared_secret: \"${DENDRITE_SHARED_SECRET}\"/" ./config/dendrite/dendrite.yaml

# generate dendrite matrix key
echo -e '\e[32mGenerating dendrite matrix key ...\e[0m'
podman container run --rm --entrypoint="" -v "$(pwd)/config/dendrite:/etc/dendrite" docker.io/matrixdotorg/dendrite-monolith:latest /usr/bin/generate-keys -private-key /etc/dendrite/matrix_key.pem

# create Matrix Facebook bridge config and registration
echo -e '\e[32mConfiguring Matrix Facebook bridge ...\e[0m'
podman container run --rm -v "$(pwd)/config/service-facebook:/data:z" dock.mau.dev/mautrix/facebook:latest
sudo sed -Ei "s/^(\s*)(address: https:\/\/example\.com.*$)/\1address: \"http:\/\/localhost:8008\"/" ./config/service-facebook/config.yaml
sudo sed -Ei "s/^(\s*)(domain: example\.com.*$)/\1domain: \"${DENDRITE_DOMAIN}\"/" ./config/service-facebook/config.yaml
sudo sed -Ei "s/^(\s*)(database: postgres:\/\/username:password@hostname\/db.*$)/\1database: \"postgres:\/\/${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost\/${POSTGRES_DATABASE_SERVICE_FACEBOOK}\"/" ./config/service-facebook/config.yaml
sudo sed -Ei "s/^(\s*)(\"example\.com\": \"user\".*$)/\1\"${DENDRITE_DOMAIN}\": \"user\"/" ./config/service-facebook/config.yaml
sudo sed -Ei "s/^(\s*)(\"@admin:example\.com\": \"admin\".*$)/\1\"@${DENDRITE_ADMIN}:${DENDRITE_DOMAIN}\": \"admin\"/" ./config/service-facebook/config.yaml
podman container run --rm -v "$(pwd)/config/service-facebook:/data:z" dock.mau.dev/mautrix/facebook:latest
cp ./config/service-facebook/registration.yaml ./config/dendrite/service-facebook-registration.yaml

# create element config
wget -qO ./config/element/config.json 'https://github.com/vector-im/element-web/raw/develop/config.sample.json'
sed -Ei "s/^(\s*)(\"base_url\"\s*:\s*\"https:\/\/matrix-client\.matrix\.org\".*$)/\1\"base_url\": \"https:\/\/${DENDRITE_DOMAIN}\",/" ./config/element/config.json
sed -Ei "s/^(\s*)(\"server_name\"\s*:.*$)/\1\"server_name\": \"${DENDRITE_DOMAIN}\"/" ./config/element/config.json
sed -Ei "s/^(\s*)(\"disable_guests\"\s*:.*$)/\1\"disable_guests\": true,/" ./config/element/config.json
sed -Ei "s/^(\s*)(\"default_country_code\"\s*:.*$)/\1\"default_country_code\": \"GR\",/" ./config/element/config.json
sed -Ei "s/^(\s*)(\"show_labs_settings\"\s*:.*$)/\1\"show_labs_settings\": true,/" ./config/element/config.json
sed -Ei "s/^(\s*)(\"default_theme\"\s*:.*$)/\1\"default_theme\": \"dark\",/" ./config/element/config.json
sed -Ei "s/^(\s*)(\"servers\"\s*:.*$)/\1\"servers\": [\"${DENDRITE_DOMAIN}\"]/" ./config/element/config.json
