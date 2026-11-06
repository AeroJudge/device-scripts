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
#   /home/judge/fetch_update.sh --recover-clock  # Temporary update time only; no update
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

# Temporary update time. A device stored between events can lose RTC time
# and then boot with a clock too far in the past for HTTPS certificate
# dates. Only when the RTC reports invalid, take the Date header from the
# update host and set the system clock. The RTC is never written; the
# helper's set-system-only keeps the kernel from copying to it. Score sets
# real time later. Any failure warns and continues so the update fails as
# it would have, with a clearer reason.
recover_clock() {
    [ -x /usr/local/sbin/aerojudge-clock ] || return 0
    [ "$(sudo -n /usr/local/sbin/aerojudge-clock status 2>/dev/null)" = invalid ] || return 0

    http_date=$(curl -sI -k --max-time 10 "$UPDATE_URL" \
        | grep -i '^date:' | cut -d' ' -f2- | tr -d '\r')
    epoch=$(date -d "$http_date" +%s 2>/dev/null)
    if [ -z "$epoch" ]; then
        echo "WARNING: could not read update host time; RTC time is invalid and the update may fail." >&2
        return 0
    fi
    if sudo -n /usr/local/sbin/aerojudge-clock set-system-only "$epoch" >/dev/null; then
        echo "Temporary update time set from update host; RTC still invalid until Score sets it."
    else
        echo "WARNING: temporary update time was not set; the update may fail." >&2
    fi
}

# The app's update check calls this mode before it contacts GitHub itself.
case "${1:-}" in
    --recover-clock)
        recover_clock
        exit 0
        ;;
esac

recover_clock

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
