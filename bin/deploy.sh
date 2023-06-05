#!/bin/bash
set -e # return a non-zero response if any of these commands fail

app_folder=/home/katehedgpeth/bird_song

cd $app_folder

# fetch latest changes
git fetch
git reset --hard origin/main

# Install dependencies
mix deps.get --only prod
cd ${app_folder}/assets
npm install
cd $app_folder

# run tests
CI=true mix test

# Set MIX_ENV so subsequent mix steps don't need to specify it
export MIX_ENV=prod

# build assets
mix assets.deploy

# Identify the currently running release
current_release=$(ls ../releases | sort -nr | head -n 1)
now_in_unix_seconds=$(date +'%s')
if [[ $current_release == '' ]]; then current_release=$now_in_unix_seconds; fi

# Create release
mix release --path ../releases/${now_in_unix_seconds}

# Get the HTTP_PORT variable from the currently running release
source ../releases/${current_release}/releases/0.1.0/env.sh
if [[ $HTTP_PORT == '4000' ]]
then
  http=4001
  https=4041
  old_port=4000
else
  http=4000
  https=4040
  old_port=4001
fi

# Put env vars with the ports to forward to, and set a non-conflicting node name.
#
# Setting a RELEASE_NAME environment variable sets the name of the node when Erlang boots up.
#
# We can’t have two nodes with the same name running simultaneously, so we just set
# the node name to the same value as the open port to avoid conflicts.
echo "export HTTP_PORT=${http}" >> ../releases/${now_in_unix_seconds}/releases/0.1.0/env.sh
echo "export HTTPS_PORT=${https}" >> ../releases/${now_in_unix_seconds}/releases/0.1.0/env.sh
echo "export RELEASE_NAME=${http}" >> ../releases/${now_in_unix_seconds}/releases/0.1.0/env.sh

# Set the release to the new version
rm ../env_vars || true
touch ../env_vars
echo "RELEASE=${now_in_unix_seconds}" >> ../env_vars

# Run migrations
mix ecto.migrate

# Boot the new version of the app
sudo systemctl start bird_song@${http}
# Wait for the new version to boot
until $(curl --output /dev/null --silent --head --fail   localhost:${http}); do
  echo 'Waiting for app to boot...'
  sleep 1
done

# Switch forwarding of ports 443 and 80 to the ones the new app is listening on
sudo iptables -t nat -R PREROUTING 1 -p tcp --dport 80 -j REDIRECT --to-port ${http}
sudo iptables -t nat -R PREROUTING 2 -p tcp --dport 443 -j REDIRECT --to-port ${https}

# Stop the old version
sudo systemctl stop bird_song@${old_port}
# Just in case the old version was started by systemd after a server
# reboot, also stop the server_reboot version
sudo systemctl stop bird_song@server_reboot
echo 'Deployed!'
