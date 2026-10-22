#!/bin/sh

SCRIPTS_RAW_BASE_URL="${AEROJUDGE_SCRIPTS_RAW_BASE_URL:-https://raw.githubusercontent.com/AeroJudge/device-scripts/main}"
RAW_BASE_URL="${AEROJUDGE_RAW_BASE_URL:-https://raw.githubusercontent.com/AeroJudge/aerojudge-device-app/main}"
APP_RELEASE_API_URL="${AEROJUDGE_APP_RELEASE_API_URL:-https://api.github.com/repos/AeroJudge/aerojudge-device-app/releases/latest}"
FIGURES_RELEASE_API_URL="${AEROJUDGE_FIGURES_RELEASE_API_URL:-https://api.github.com/repos/AeroJudge/device-figures-pkg/releases/latest}"
VOLUME_RELEASE_API_URL="${AEROJUDGE_VOLUME_RELEASE_API_URL:-https://api.github.com/repos/AeroJudge/device-volume-svc/releases/latest}"

# Sources are independent: old base-image launchers export the app source.
while [ "${SCRIPTS_RAW_BASE_URL%/}" != "$SCRIPTS_RAW_BASE_URL" ]; do SCRIPTS_RAW_BASE_URL=${SCRIPTS_RAW_BASE_URL%/}; done
while [ "${RAW_BASE_URL%/}" != "$RAW_BASE_URL" ]; do RAW_BASE_URL=${RAW_BASE_URL%/}; done
export AEROJUDGE_SCRIPTS_RAW_BASE_URL="$SCRIPTS_RAW_BASE_URL"
export AEROJUDGE_RAW_BASE_URL="$RAW_BASE_URL"
export AEROJUDGE_APP_RELEASE_API_URL="$APP_RELEASE_API_URL"
export AEROJUDGE_FIGURES_RELEASE_API_URL="$FIGURES_RELEASE_API_URL"
export AEROJUDGE_VOLUME_RELEASE_API_URL="$VOLUME_RELEASE_API_URL"

#
# The following fixes some ownership errors that some devices had, removes all old contest data, and performs a device upgrade
#

sudo chown judge:judge .judge_last_release
sudo chown -R judge:judge /var/opt/judge
sudo chmod -R go-w /var/opt/judge/

cd /var/opt/judge
rm *.log *.dat *.zip *.json
rm pilots/scores/*

cd ~
rm .judge_last_release
curl -sfS "$SCRIPTS_RAW_BASE_URL/fetch_update.sh" -o /home/judge/fetch_update.sh
chmod +x /home/judge/fetch_update.sh
/home/judge/fetch_update.sh

# Fix default network settings to match AeroJudge config
# Comment out this line if running manually to keep the original (deprecated) defaults
sed -i 's/"score_host":"192.168.1.4"/"score_host":"192.168.8.100"/;s/"score_http_port":8181/"score_http_port":80/' /var/opt/judge/settings.json

# removes this script so it doesn't get accidentally run again
rm device_reset.sh