#!/bin/bash
#
# Current AeroJudge fresh-device setup script.
# The previous legacy setup script is preserved as judge_setup_legacy.sh.

set -Eeuo pipefail

LOG_FILE="/home/judge/aerojudge-setup.log"
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

INSTALL_DIR="/var/opt/judge"
BIN_DIR="$INSTALL_DIR/bin"
SETTINGS_FILE="$INSTALL_DIR/settings.json"
BOOT_CONFIG="/boot/config.txt"
BOOT_CONFIG_BACKUP="/boot/config.txt.before-aerojudge"
IDENTITY_TOOL="/tmp/device_identity.sh"
NVMEM="/sys/bus/nvmem/devices/rv3028_eeprom0/nvmem"
DEVICE_IDENTITY=""
SEASON_YEAR=""

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

exec > >(tee -a "$LOG_FILE") 2>&1

fail() {
    echo -e "${RED}ERROR:${NC} $*" >&2
    echo "Setup failed. See $LOG_FILE"
    exit 1
}

on_error() {
    local line_no="$1"
    fail "Unexpected failure at line $line_no."
}

trap 'on_error "$LINENO"' ERR

step() {
    echo
    echo -e "${YELLOW}[$1]${NC} $2"
}

download() {
    local url="$1"
    local output="$2"

    echo "Downloading $url"
    wget -q -O "$output" "$url" || fail "Could not download $url"
}

confirm_target() {
    clear
    echo -e "${GREEN}AeroJudge Device Fresh Install${NC}"
    echo
    echo "Target hardware:"
    echo "  - AeroJudge Device serial DPG-110 and above"
    echo "  - AeroJudge PCB revision 3.61+"
    echo "  - Raspberry Pi 4B"
    echo "  - Raspberry Pi OS Bullseye 32-bit Desktop"
    echo
    echo -e "${RED}This script is for clean fresh installs only.${NC}"
    echo "Do not run it on legacy devices or existing deployed devices."
    echo
    echo "Setup first asks for the board identity and the season year,"
    echo "then installs without further input until it offers to reboot."
    echo
    echo "Type CONFIRM to continue:"
    read -r response
    [ "$response" = "CONFIRM" ] || fail "Setup cancelled."
}

verify_target() {
    step "1/12" "Verifying target OS, user, and fresh install state"

    [ -f /etc/os-release ] || fail "/etc/os-release not found."
    # shellcheck disable=SC1091
    . /etc/os-release

    [ "${VERSION_CODENAME:-}" = "bullseye" ] || fail "This setup requires Raspberry Pi OS Bullseye."
    [ "$(getconf LONG_BIT)" = "32" ] || fail "This setup requires a 32-bit OS."
    [ "$(id -un)" = "judge" ] || fail "This setup must be run as user judge."

    [ ! -d "$INSTALL_DIR" ] || fail "$INSTALL_DIR already exists. Reimage the SD card before running fresh setup."
    [ ! -e /home/judge/.judge_last_release ] || fail "/home/judge/.judge_last_release already exists. Reimage the SD card before running fresh setup."
    [ ! -d /var/opt/volume_service ] || fail "/var/opt/volume_service already exists. Reimage the SD card before running fresh setup."
    [ ! -e "$BOOT_CONFIG_BACKUP" ] || fail "$BOOT_CONFIG_BACKUP already exists. Reimage the SD card before running fresh setup."

    echo "OS: ${PRETTY_NAME:-unknown}"
    echo "Architecture bits: $(getconf LONG_BIT)"
    echo "User: $(id -un)"
}

collect_inputs() {
    step "2/12" "Collecting build inputs"

    local confirm_year

    curl -fsSL "$SCRIPTS_RAW_BASE_URL/device_identity.sh" -o "$IDENTITY_TOOL" \
        || fail "Could not download device_identity.sh"

    # The base image boots without I2C or the RTC overlay. Load them for this
    # session only; the installed boot config brings them up after reboot.
    if [ ! -e "$NVMEM" ]; then
        sudo dtparam i2c_arm=on || fail "Could not enable I2C for the board EEPROM."
        sudo dtoverlay i2c-rtc rv3028 || fail "Could not load the RTC overlay for the board EEPROM."
    fi

    # Provision board identity before app installation. Board identity can determine which app components are installed.
    # A board with an existing valid record is shown and not asked for, it cannot be replaced during setup.
    sudo bash "$IDENTITY_TOOL" write || fail "Board identity was not provisioned."
    DEVICE_IDENTITY=$(bash "$IDENTITY_TOOL" read) || fail "Board identity could not be read."

    echo
    while true; do
        echo -e "${BLUE}Enter two digit season year, for 2026 enter 26:${NC}"
        read -r SEASON_YEAR

        if [[ ! "$SEASON_YEAR" =~ ^[2-3][0-9]$ ]]; then
            echo "Season year must be two digits."
            continue
        fi

        while true; do
            read -r -p "Season year entered: $SEASON_YEAR. Is this correct? [y/n] " confirm_year
            case "$confirm_year" in
                [Yy]|[Yy][Ee][Ss])
                    break 2
                    ;;
                [Nn]|[Nn][Oo])
                    echo "Re-enter season year."
                    break
                    ;;
                *)
                    echo "Please answer y or n."
                    ;;
            esac
        done
    done

    echo
    echo -e "${GREEN}Inputs collected. Building now; no further input is needed until the reboot prompt.${NC}"
}

expand_root_filesystem() {
    step "3/12" "Expanding root filesystem"

    if command -v raspi-config >/dev/null 2>&1; then
        sudo raspi-config --expand-rootfs || fail "Root filesystem expansion failed."
        echo "Root filesystem expansion requested. Final resize may complete after reboot."
    else
        fail "raspi-config is not available; cannot expand root filesystem."
    fi
}

install_packages() {
    step "4/12" "Installing required packages"

    sudo apt-get update
    sudo apt-get install -y \
        openjdk-17-jre \
        chromium-browser \
        xdotool \
        unclutter \
        vim \
        sed \
        locate \
        unzip \
        curl \
        wget \
        alsa-utils \
        python3 \
        python3-evdev \
        evtest \
        pcmanfm

    # locate is installed for field debugging, but setup does not build its
    # database. If needed during an event, run `sudo updatedb` over SSH.
}

verify_network_access() {
    step "5/12" "Verifying repository and release access"

    local config_url="$SCRIPTS_RAW_BASE_URL/config/profiles/pcb-3.61/config.txt"

    wget -q --spider "$config_url" || fail "Cannot reach setup config: $config_url"
    wget -q --spider "$APP_RELEASE_API_URL" || fail "Cannot reach app release API: $APP_RELEASE_API_URL"
    wget -q --spider "$FIGURES_RELEASE_API_URL" || fail "Cannot reach figures release API: $FIGURES_RELEASE_API_URL"
    wget -q --spider "$VOLUME_RELEASE_API_URL" || fail "Cannot reach volume release API: $VOLUME_RELEASE_API_URL"

    echo "Scripts source: $SCRIPTS_RAW_BASE_URL"
    echo "App source: $RAW_BASE_URL"
    echo "App release API URL: $APP_RELEASE_API_URL"
    echo "Figures release API URL: $FIGURES_RELEASE_API_URL"
    echo "Volume release API URL: $VOLUME_RELEASE_API_URL"
}

install_boot_config() {
    step "6/12" "Installing AeroJudge boot config"

    local tmp_config="/tmp/aerojudge-config.txt"

    download "$SCRIPTS_RAW_BASE_URL/config/profiles/pcb-3.61/config.txt" "$tmp_config"
    [ -s "$tmp_config" ] || fail "Downloaded config file is empty."

    sudo cp "$BOOT_CONFIG" "$BOOT_CONFIG_BACKUP"
    sudo install -m 0644 "$tmp_config" "$BOOT_CONFIG"

    echo "Backed up original boot config to $BOOT_CONFIG_BACKUP"
    echo "Installed AeroJudge boot config to $BOOT_CONFIG"
}

create_settings() {
    step "7/12" "Creating device settings"

    local judge_id="1"
    local line_number="1"
    local score_host="192.168.8.100"
    local score_http_port="80"
    local language="en"
    local score_poll_timeout="2"
    local score_timeout="10"

    echo
    echo "Settings to write:"
    echo "  judge_id: $judge_id"
    echo "  line_number: $line_number"
    echo "  score_host: $score_host"
    echo "  score_http_port: $score_http_port"
    echo "  language: $language"
    echo "  score_poll_timeout: $score_poll_timeout"
    echo "  score_timeout: $score_timeout"
    echo "  seasonYear: $SEASON_YEAR"
    echo

    sudo mkdir -p "$BIN_DIR" "$INSTALL_DIR/pilots/scores"
    sudo chown -R judge:judge "$INSTALL_DIR"

    cat > /tmp/aerojudge-settings.json <<EOF
{
  "judge_id": $judge_id,
  "line_number": $line_number,
  "score_host": "$score_host",
  "score_http_port": $score_http_port,
  "language": "$language",
  "score_poll_timeout": $score_poll_timeout,
  "score_timeout": $score_timeout,
  "seasonYear": $SEASON_YEAR
}
EOF

    install -m 0644 /tmp/aerojudge-settings.json "$SETTINGS_FILE"
    chown judge:judge "$SETTINGS_FILE"

    echo "Created $SETTINGS_FILE"
}

install_runtime_files() {
    step "8/12" "Installing services, scripts, and desktop image"

    local tmp_dir="/tmp/aerojudge-setup-files"
    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"

    download "$RAW_BASE_URL/scripts/judge.service" "$tmp_dir/judge.service"
    download "$RAW_BASE_URL/scripts/judge.sh" "$tmp_dir/judge.sh"
    download "$RAW_BASE_URL/scripts/kiosk.service" "$tmp_dir/kiosk.service"
    download "$RAW_BASE_URL/scripts/kiosk.sh" "$tmp_dir/kiosk.sh"
    download "$SCRIPTS_RAW_BASE_URL/fetch_update.sh" "$tmp_dir/fetch_update.sh"
    download "$SCRIPTS_RAW_BASE_URL/assets/ajdesktop.png" "$tmp_dir/ajdesktop.png"

    sudo install -m 0644 "$tmp_dir/judge.service" /lib/systemd/system/judge.service
    install -m 0755 "$tmp_dir/judge.sh" "$BIN_DIR/judge.sh"
    sudo install -m 0644 "$tmp_dir/kiosk.service" /lib/systemd/system/kiosk.service
    install -m 0755 "$tmp_dir/kiosk.sh" "$BIN_DIR/kiosk.sh"
    install -m 0755 "$tmp_dir/fetch_update.sh" /home/judge/fetch_update.sh
    install -m 0644 "$tmp_dir/ajdesktop.png" /home/judge/ajdesktop.png
    hide_desktop_wastebasket

    sudo systemctl daemon-reload

    if DISPLAY=:0 XAUTHORITY=/home/judge/.Xauthority pcmanfm --set-wallpaper /home/judge/ajdesktop.png --wallpaper-mode=stretch; then
        echo "Desktop wallpaper configured."
    else
        echo "WARNING: Desktop image was installed, but wallpaper configuration did not complete."
        echo "This can happen when no desktop session is active over SSH."
    fi
}

hide_desktop_wastebasket() {
    local pcmanfm_config_dir="/home/judge/.config/pcmanfm/LXDE-pi"
    local desktop_config="$pcmanfm_config_dir/desktop-items-0.conf"

    mkdir -p "$pcmanfm_config_dir"

    if [ ! -s "$desktop_config" ]; then
        printf "[*]\nshow_trash=0\n" > "$desktop_config"
    elif grep -q "^show_trash=" "$desktop_config"; then
        sed -i "s/^show_trash=.*/show_trash=0/" "$desktop_config"
    else
        printf "\nshow_trash=0\n" >> "$desktop_config"
    fi

    chown -R judge:judge /home/judge/.config/pcmanfm

    if DISPLAY=:0 XAUTHORITY=/home/judge/.Xauthority \
        pcmanfm --reconfigure --profile LXDE-pi; then
        echo "Desktop Wastebasket icon hidden."
    else
        echo "WARNING: Wastebasket setting was saved, but the desktop did not reload."
        echo "The setting will apply when the judge desktop next starts."
    fi
}

disable_desktop_update_prompts() {
    # Field devices are updated intentionally through AeroJudge release flow or SSH,
    # not by tapping desktop PackageKit prompts during boot.
    sudo systemctl disable --now packagekit.service 2>/dev/null || true
    sudo systemctl mask packagekit.service 2>/dev/null || true
    sudo systemctl disable --now packagekit-offline-update.service 2>/dev/null || true
    sudo systemctl mask packagekit-offline-update.service 2>/dev/null || true
    echo "Desktop PackageKit update prompts disabled."
}

install_release_assets() {
    step "9/12" "Installing latest AeroJudge release assets"

    run_update_phase --download-only
    run_update_phase --install
}

run_update_phase() {
    local mode="$1"
    local exit_code

    if /home/judge/fetch_update.sh "$mode"; then
        exit_code=0
    else
        exit_code=$?
    fi

    case "$exit_code" in
        0|2)
            ;;
        *)
            fail "fetch_update.sh $mode failed with exit code $exit_code."
            ;;
    esac
}

enable_services() {
    step "10/12" "Enabling services"

    sudo systemctl enable judge.service
    sudo systemctl enable kiosk.service
}

validate_install() {
    step "11/12" "Validating installed files and services"

    [ -s "$BIN_DIR/judge.jar" ] || fail "$BIN_DIR/judge.jar is missing."
    [ -s "$INSTALL_DIR/figures/en/audio/instructions.mp3" ] || fail "Figures/audio assets are missing."
    [ -d "$INSTALL_DIR/pilots" ] || fail "$INSTALL_DIR/pilots directory is missing."
    [ -d "$INSTALL_DIR/pilots/scores" ] || fail "$INSTALL_DIR/pilots/scores directory is missing."
    [ -s /var/opt/volume_service/volume.py ] || fail "Volume service script is missing."
    [ -s /var/opt/volume_service/tone-up.wav ] || fail "Volume tone-up file is missing."
    [ -s /var/opt/volume_service/tone-down.wav ] || fail "Volume tone-down file is missing."
    [ -x /usr/local/sbin/aerojudge-audio-hardware ] || fail "Audio hardware helper is missing or not executable."
    [ -s /etc/systemd/system/audio-hardware.service ] || fail "Audio hardware service unit is missing."
    [ -s /etc/systemd/system/volume.service ] || fail "Volume service unit is missing."

    python3 -c "import evdev" || fail "python3-evdev is not available."
    python3 -m py_compile /var/opt/volume_service/volume.py || fail "Volume service Python syntax validation failed."
    sudo /bin/sh -n /usr/local/sbin/aerojudge-audio-hardware || fail "Audio hardware helper syntax validation failed."
    sudo systemd-analyze verify \
        /etc/systemd/system/audio-hardware.service \
        /etc/systemd/system/volume.service || fail "Audio service unit validation failed."

    grep -q '^gpio=8=op,dl$' "$BOOT_CONFIG" || fail "Boot config does not hold GPIO8 output-low."
    grep -q '^dtparam=audio=off$' "$BOOT_CONFIG" || fail "Boot config does not disable onboard audio."
    grep -q '^dtoverlay=hifiberry-dacplus$' "$BOOT_CONFIG" || fail "Boot config does not enable the HiFiBerry DAC."
    if grep -Eq '^[[:space:]]*dtoverlay=gpio-key,gpio=20([,[:space:]]|$)' "$BOOT_CONFIG"; then
        fail "Boot config enables GPIO20 DEADLINE, which conflicts with the I2S DAC."
    fi

    systemctl is-enabled judge.service >/dev/null || fail "judge.service is not enabled."
    systemctl is-enabled kiosk.service >/dev/null || fail "kiosk.service is not enabled."
    systemctl is-enabled audio-hardware.service >/dev/null || fail "audio-hardware.service is not enabled."
    systemctl is-enabled volume.service >/dev/null || fail "volume.service is not enabled."

    echo "Install validation passed."
}

finish() {
    # Validation passed; remove only the one-time device setup entry points.
    rm -f -- /home/judge/build_aerojudge.sh /home/judge/judge_setup.sh

    step "12/12" "Setup complete"

    echo
    echo -e "${GREEN}AeroJudge Device setup completed.${NC}"
    echo
    echo "A reboot is required so /boot/config.txt hardware settings take effect."
    echo "After reboot, validate:"
    echo "  - kiosk opens AeroJudge"
    echo "  - http://<pi-ip>:8080 loads from another machine"
    echo "  - fresh device opens /newcomp"
    echo "  - Set Line and Judge number"
    echo "Load event from score to validate:"
    echo "  - GPIO scoring buttons work"
    echo "  - volume thumbwheel works"
    echo "  - audio playback works"
    echo "  - shutdown/poweroff behavior works"
    echo
    echo "Audio checks after reboot:"
    echo "  systemctl is-active audio-hardware.service volume.service"
    echo "  amixer -c sndrpihifiberry get Digital"
    echo "  raspi-gpio get 8"
    echo "  pactl info | grep -E 'Server Name|Default Sink'"
    echo "  journalctl -u audio-hardware.service -u volume.service -n 80 --no-pager"
    echo
    echo "Board identity: $DEVICE_IDENTITY"
    echo "Settings file: $SETTINGS_FILE"
    echo "Setup log: $LOG_FILE"
    echo
    read -r -p "Reboot now? [y/N] " reboot_now
    case "$reboot_now" in
        [Yy]|[Yy][Ee][Ss])
            sudo reboot
            ;;
        *)
            echo "Reboot skipped. Run: sudo reboot"
            ;;
    esac
}

confirm_target
verify_target
collect_inputs
expand_root_filesystem
disable_desktop_update_prompts
install_packages
verify_network_access
install_boot_config
create_settings
install_runtime_files
install_release_assets
enable_services
validate_install
finish
