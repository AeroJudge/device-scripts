#!/bin/bash
#
# AeroJudge setup launcher for prepared base images.
# This script fetches the current judge_setup.sh and runs it.

set -Eeuo pipefail

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
SETUP_SCRIPT="/home/judge/judge_setup.sh"

cd /home/judge

echo "Fetching AeroJudge setup script from:"
echo "  $SCRIPTS_RAW_BASE_URL/judge_setup.sh"
echo "App release API:"
echo "  $APP_RELEASE_API_URL"
echo "Figures release API:"
echo "  $FIGURES_RELEASE_API_URL"
echo "Volume release API:"
echo "  $VOLUME_RELEASE_API_URL"

curl -fsSL "$SCRIPTS_RAW_BASE_URL/judge_setup.sh" -o "$SETUP_SCRIPT"
chmod +x "$SETUP_SCRIPT"

echo
echo "Starting AeroJudge setup..."
exec "$SETUP_SCRIPT"
