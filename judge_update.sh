#!/bin/sh
# =============================================================================
# judge_update.sh - AeroJudge Update Script
# =============================================================================
# Checks the app release feed for a new version and installs judge.jar, figures.zip and volume_service.zip from their own release feeds.
# It is fetched and executed by fetch_update.sh on the device.
#
# Modes:
#   --download-only  Check for update + download assets to /tmp/judge-update/
#   --install        Backup + install from /tmp/judge-update/ + health check
#   (no flag)        Legacy: runs full download-then-install (original behavior)
#
# Exit Codes:
#   0 = No update needed (already running latest version)
#   1 = Error occurred
#   2 = Update assets downloaded (--download-only) or update applied (--install/legacy)
# =============================================================================

INSTALL_DIR="/var/opt/judge"
BIN_DIR="$INSTALL_DIR/bin"
STAGING_DIR="/tmp/judge-update"
LOG_FILE="/tmp/judge-update.log"
HEALTH_URL="http://localhost:8080/actuator/health"
HEALTH_RETRIES=30
HEALTH_INTERVAL=5
VERSION_FILE="/home/judge/.judge_last_release"
MODE="$1"
APP_RELEASE_API_URL="${AEROJUDGE_APP_RELEASE_API_URL:-https://api.github.com/repos/AeroJudge/aerojudge-device-app/releases/latest}"
FIGURES_RELEASE_API_URL="${AEROJUDGE_FIGURES_RELEASE_API_URL:-https://api.github.com/repos/AeroJudge/device-figures-pkg/releases/latest}"
VOLUME_RELEASE_API_URL="${AEROJUDGE_VOLUME_RELEASE_API_URL:-https://api.github.com/repos/AeroJudge/device-volume-svc/releases/latest}"
STABLE_TAG_PATTERN='^v[0-9]{2}\.[0-9]+\.[0-9]+$'

# ---- Shared functions -------------------------------------------------------

# Release tags are update/install state and keep the leading v in
# /home/judge/.judge_last_release.
is_stable_release_tag() {
    echo "$1" | grep -Eq "$STABLE_TAG_PATTERN"
}

# Function to compare stable release tags in format vYY.MAJOR.MINOR
# Returns: 0 if version1 > version2, 1 otherwise
compare_versions() {
    local version1=$1
    local version2=$2

    # Remove 'v' prefix if present
    version1=$(echo "$version1" | sed 's/^v//')
    version2=$(echo "$version2" | sed 's/^v//')

    # Compare versions numerically using awk
    result=$(awk -v v1="$version1" -v v2="$version2" 'BEGIN {
        split(v1, a, ".")
        split(v2, b, ".")
        for (i = 1; i <= 3; i++) {
            if (a[i] == "") a[i] = 0
            if (b[i] == "") b[i] = 0
            if (a[i]+0 > b[i]+0) { print 0; exit }
            if (a[i]+0 < b[i]+0) { print 1; exit }
        }
        print 1
    }')

    return "$result"
}

# Download one named asset from a release feed (GitHub releases API JSON)
# into the staging directory. Fails visibly when the asset is not listed or
# the download does not complete; the caller cleans staging.
download_release_asset() {
    feed_json=$1
    asset_name=$2

    asset_url=$(echo "$feed_json" | grep -oP '"browser_download_url": "[^"]*/'"$asset_name"'"' | head -n 1 | cut -d' ' -f2 | tr -d '"')
    if [ -z "$asset_url" ]; then
        echo "Asset $asset_name is not listed in the release feed!" >&2
        return 1
    fi

    echo "Downloading asset: $asset_url"
    curl --silent --fail -L -o "$STAGING_DIR/$asset_name" "$asset_url"
    if [ $? -ne 0 ]; then
        echo "Error fetching asset: $asset_url" >&2
        return 1
    fi
}

# Read the version from an installed package.json without jq.
package_version() {
    grep -o '"version": *"[^"]*"' "$1" 2>/dev/null | head -n 1 | cut -d'"' -f4
}

ensure_judge_dir() {
    if [ ! -d "$INSTALL_DIR" ]; then
        echo "Creating judge folder..."
        sudo mkdir -p "$INSTALL_DIR"
    fi

    if [ "$(stat -c '%U' "$INSTALL_DIR")" != "judge" ]; then
        echo "Changing owner of judge folder..."
        sudo chown -R judge:judge "$INSTALL_DIR"
        echo "Changing judge service to use judge owner..."
        sudo sed -i 's/User=root/User=judge/g' /lib/systemd/system/judge.service
        sudo systemctl daemon-reload
    fi
}

# Install the hardware-specific audio stack if not already present.
# Must be called BEFORE staging directory is cleaned up.
check_volume_service() {
    if [ ! -d /var/opt/volume_service ]; then
        if [ -f "$STAGING_DIR/volume_service.zip" ] || [ -f volume_service.zip ]; then
            VZIP="${STAGING_DIR}/volume_service.zip"
            [ ! -f "$VZIP" ] && VZIP="volume_service.zip"

            echo "Installing PCB 3.61+ audio and volume services..."
            sudo mkdir -p /var/opt/volume_service
            sudo chown judge:judge /var/opt/volume_service
            unzip -quoj "$VZIP" -d /var/opt/volume_service/
            rm -f "$VZIP"
            echo "Installed volume service package $(package_version /var/opt/volume_service/package.json)"

            [ -s /var/opt/volume_service/audio_hardware.sh ] || {
                echo "Audio hardware helper is missing from volume_service.zip" >&2
                return 1
            }
            [ -s /var/opt/volume_service/audio-hardware.service ] || {
                echo "audio-hardware.service is missing from volume_service.zip" >&2
                return 1
            }
            [ -s /var/opt/volume_service/volume.service ] || {
                echo "volume.service is missing from volume_service.zip" >&2
                return 1
            }

            sudo install -o root -g root -m 0755 \
                /var/opt/volume_service/audio_hardware.sh \
                /usr/local/sbin/aerojudge-audio-hardware
            sudo install -o root -g root -m 0644 \
                /var/opt/volume_service/audio-hardware.service \
                /etc/systemd/system/audio-hardware.service
            sudo install -o root -g root -m 0644 \
                /var/opt/volume_service/volume.service \
                /etc/systemd/system/volume.service

            rm -f \
                /var/opt/volume_service/audio_hardware.sh \
                /var/opt/volume_service/audio-hardware.service \
                /var/opt/volume_service/volume.service

            sudo systemctl daemon-reload
            sudo systemctl enable audio-hardware.service volume.service
            echo "Audio services enabled; they will start after the required reboot."
        else
            echo "No volume_service.zip staged; audio stack not installed"
        fi
    fi
}

# Check for xset in .bashrc (disables key repeat after reboot)
check_xset() {
    if ! grep -q "xset r off" /home/judge/.bashrc; then
        echo "export DISPLAY=:0" >> /home/judge/.bashrc
        echo "xset r off" >> /home/judge/.bashrc
        export DISPLAY=:0
        xset r off
    fi
}

# ---- Download phase ---------------------------------------------------------
# Uses `return` (not `exit`) so the caller can act on the result.
# Only the main block at the bottom calls `exit`.

do_download() {
    ensure_judge_dir

    if [ ! -f "$VERSION_FILE" ]; then
        touch "$VERSION_FILE"
    fi

    last_release=$(cat "$VERSION_FILE")

    latest_release=$(curl --silent --fail -G "$APP_RELEASE_API_URL")
    if [ $? -ne 0 ]; then
        echo "Error fetching app release feed (no internet?)!" >&2
        return 1
    fi

    latest_tag=$(echo $latest_release | grep -oP '"tag_name": "(.*?)"' | cut -d' ' -f2 | tr -d [\"])
    if [ $? -ne 0 ] || [ -z "$latest_tag" ]; then
        echo "Error parsing latest release tag from release feed!" >&2
        return 1
    fi

    # Refuse malformed latest tags before comparing or staging assets.
    if ! is_stable_release_tag "$latest_tag"; then
        echo "Invalid latest release tag: $latest_tag" >&2
        echo "Expected stable release tag format: vYY.MAJOR.MINOR, for example v26.1.0" >&2
        return 1
    fi

    # A malformed marker means the update state is not trustworthy.
    if [ -n "$last_release" ] && ! is_stable_release_tag "$last_release"; then
        echo "Invalid installed release marker in $VERSION_FILE: $last_release" >&2
        echo "Expected stable release tag format: vYY.MAJOR.MINOR, for example v26.1.0" >&2
        return 1
    fi

    echo "Current version: $last_release"
    echo "Latest version: $latest_tag"

    if [ -z "$last_release" ] || compare_versions "$latest_tag" "$last_release"; then
        echo "New release found: $latest_tag"

        # Clean staging directory — fresh download every time
        rm -rf "$STAGING_DIR"
        mkdir -p "$STAGING_DIR"

        echo "Downloading assets to $STAGING_DIR..."

        # Each component comes from its own release feed. One all-or-nothing
        # download phase: any failure removes staging before anything installs.
        download_release_asset "$latest_release" judge.jar || { rm -rf "$STAGING_DIR"; return 1; }

        figures_release=$(curl --silent --fail -G "$FIGURES_RELEASE_API_URL")
        if [ $? -ne 0 ]; then
            echo "Error fetching figures release feed (no internet?)!" >&2
            rm -rf "$STAGING_DIR"
            return 1
        fi
        download_release_asset "$figures_release" figures.zip || { rm -rf "$STAGING_DIR"; return 1; }

        volume_release=$(curl --silent --fail -G "$VOLUME_RELEASE_API_URL")
        if [ $? -ne 0 ]; then
            echo "Error fetching volume release feed (no internet?)!" >&2
            rm -rf "$STAGING_DIR"
            return 1
        fi
        download_release_asset "$volume_release" volume_service.zip || { rm -rf "$STAGING_DIR"; return 1; }

        # Write the target version to staging so the install phase knows it
        echo "$latest_tag" > "$STAGING_DIR/.target_version"

        echo "Download complete. Assets staged in $STAGING_DIR"
        return 2  # Assets ready for install
    else
        echo "Latest version already installed"
        return 0
    fi
}

# ---- Install phase ----------------------------------------------------------
# Uses `return` (not `exit`) so post-install checks can run after it.

do_install() {
    ensure_judge_dir

    # Verify staging directory exists with assets
    if [ ! -d "$STAGING_DIR" ]; then
        echo "Error: staging directory $STAGING_DIR does not exist. Run --download-only first." >&2
        return 1
    fi

    TARGET_VERSION=""
    if [ -f "$STAGING_DIR/.target_version" ]; then
        TARGET_VERSION=$(cat "$STAGING_DIR/.target_version")
    fi
    echo "Installing update: $TARGET_VERSION"

    # Install only a staged stable release tag written during download.
    if ! is_stable_release_tag "$TARGET_VERSION"; then
        echo "Invalid staged target release tag: $TARGET_VERSION" >&2
        echo "Expected stable release tag format: vYY.MAJOR.MINOR, for example v26.1.0" >&2
        return 1
    fi

    # Backup current JAR before touching anything
    BACKUP_CREATED=false
    if [ -f "$BIN_DIR/judge.jar" ]; then
        cp "$BIN_DIR/judge.jar" "$BIN_DIR/judge.jar.bak"
        echo "Backup created: $BIN_DIR/judge.jar.bak"
        BACKUP_CREATED=true
    fi

    echo "Stopping services..."
    sudo systemctl stop judge.service

    # Install assets from staging
    if [ -f "$STAGING_DIR/judge.jar" ]; then
        mv "$STAGING_DIR/judge.jar" "$BIN_DIR/judge.jar"
        echo "Installed judge.jar version $TARGET_VERSION"
    fi

    if [ -f "$STAGING_DIR/figures.zip" ]; then
        rm -rf "$INSTALL_DIR/figures"
        unzip -qo "$STAGING_DIR/figures.zip" -d "$INSTALL_DIR"
        echo "Installed figures package $(package_version "$INSTALL_DIR/figures/package.json")"
    fi

    # Install the hardware-specific audio stack before cleaning up staging;
    # it reads volume_service.zip from the staging directory.
    check_volume_service || return 1

    echo "Starting services..."
    sudo systemctl start judge.service

    # Health check — wait for Spring Boot to respond
    echo "Waiting for service to become healthy..."
    HEALTHY=false
    for i in $(seq 1 $HEALTH_RETRIES); do
        sleep $HEALTH_INTERVAL
        HTTP_STATUS=$(curl --silent --output /dev/null --write-out "%{http_code}" "$HEALTH_URL" 2>/dev/null)
        if [ "$HTTP_STATUS" = "200" ]; then
            echo "Health check passed (attempt $i/$HEALTH_RETRIES)"
            HEALTHY=true
            break
        fi
        echo "Health check attempt $i/$HEALTH_RETRIES — status: $HTTP_STATUS"
    done

    if [ "$HEALTHY" = true ]; then
        # Write version marker only AFTER confirmed healthy. Previously this was
        # written before downloading assets — if the download failed, the device
        # would think it was already updated and never retry.
        echo "$TARGET_VERSION" > "$VERSION_FILE"
        echo "Version marker updated to $TARGET_VERSION"

        # Clean up staging
        rm -rf "$STAGING_DIR"

        # Refresh the kiosk browser to show the updated app
        DISPLAY=:0 xdotool search --onlyvisible --class chromium key F5

        echo "Update complete and verified healthy!"
        return 2

    else
        # ROLLBACK — new version failed to start
        echo "HEALTH CHECK FAILED — rolling back!" >&2

        if [ "$BACKUP_CREATED" = true ]; then
            echo "Restoring backup..."
            sudo systemctl stop judge.service
            cp "$BIN_DIR/judge.jar.bak" "$BIN_DIR/judge.jar"
            sudo systemctl start judge.service

            # Verify rollback health — same retry window as the main health check
            echo "Verifying rollback..."
            ROLLBACK_OK=false
            for i in $(seq 1 $HEALTH_RETRIES); do
                sleep $HEALTH_INTERVAL
                ROLLBACK_STATUS=$(curl --silent --output /dev/null --write-out "%{http_code}" "$HEALTH_URL" 2>/dev/null)
                if [ "$ROLLBACK_STATUS" = "200" ]; then
                    echo "Rollback successful — service restored to previous version (attempt $i/$HEALTH_RETRIES)"
                    ROLLBACK_OK=true
                    # Refresh the kiosk browser to show the restored app
                    DISPLAY=:0 xdotool search --onlyvisible --class chromium key F5
                    break
                fi
                echo "Rollback health check attempt $i/$HEALTH_RETRIES — status: $ROLLBACK_STATUS"
            done
            if [ "$ROLLBACK_OK" = false ]; then
                echo "WARNING: Rollback health check did not pass within 150s — manual check recommended" >&2
            fi
        else
            echo "WARNING: No backup available to restore!" >&2
        fi

        # Do NOT update version marker — next attempt will retry
        rm -rf "$STAGING_DIR"
        return 1
    fi
}

# ---- Main -------------------------------------------------------------------
# All `exit` calls are here — functions use `return` so they compose correctly.

case "$MODE" in
    --download-only)
        do_download
        exit $?
        ;;
    --install)
        do_install
        INSTALL_EXIT=$?
        check_xset
        exit $INSTALL_EXIT
        ;;
    *)
        # Legacy mode: download + install in one pass.
        # Backwards compatible with devices that have old fetch_update.sh.
        do_download
        DOWNLOAD_EXIT=$?
        if [ "$DOWNLOAD_EXIT" -eq 2 ]; then
            do_install
            INSTALL_EXIT=$?
            # check_volume_service already called inside do_install
            check_xset
            exit $INSTALL_EXIT
        else
            exit $DOWNLOAD_EXIT
        fi
        ;;
esac
