#!/bin/sh
# =============================================================================
# fetch_update.sh - AeroJudge Update Fetcher
# =============================================================================
# This script is installed on the device and fetches/executes the latest
# update script from GitHub. This allows the main update logic to be
# updated remotely without needing to modify files on individual devices.
#
# Usage:
#   /home/judge/fetch_update.sh                  # Legacy: full update (download + install)
#   /home/judge/fetch_update.sh --download-only  # Phase 1: check + download assets
#   /home/judge/fetch_update.sh --install        # Phase 2: backup, install, health check
#
# Exit Codes (passed through from judge_update.sh):
#   0 = No update needed (already running latest version)
#   1 = Error occurred during update
#   2 = Update successfully applied / assets downloaded and ready
# =============================================================================

SCRIPTS_RAW_BASE_URL="${AEROJUDGE_SCRIPTS_RAW_BASE_URL:-https://raw.githubusercontent.com/AeroJudge/device-scripts/main}"
while [ "${SCRIPTS_RAW_BASE_URL%/}" != "$SCRIPTS_RAW_BASE_URL" ]; do SCRIPTS_RAW_BASE_URL=${SCRIPTS_RAW_BASE_URL%/}; done
export AEROJUDGE_SCRIPTS_RAW_BASE_URL="$SCRIPTS_RAW_BASE_URL"
UPDATE_URL="$SCRIPTS_RAW_BASE_URL/judge_update.sh"

# Download the update script to a temp file so we can pass arguments to it.
# The previous `curl | bash` pattern could not forward arguments.
SCRIPT_FILE=$(mktemp /tmp/judge_update_XXXXXX.sh)
curl -sfS "$UPDATE_URL" -o "$SCRIPT_FILE"
CURL_EXIT=$?

if [ $CURL_EXIT -ne 0 ]; then
    echo "Error fetching update script (no internet?)" >&2
    rm -f "$SCRIPT_FILE"
    exit 1
fi

chmod +x "$SCRIPT_FILE"
bash "$SCRIPT_FILE" "$@"
EXIT_CODE=$?

rm -f "$SCRIPT_FILE"
exit $EXIT_CODE
