# NEW AeroJudge Device Setup Procedure

These instructions are for current AeroJudge Device hardware:

- Device serial numbers `DPG-110` and above
- PCB revision `3.61`
- Raspberry Pi 4B


## Write the base image and build the AeroJudge Application

1. Download the current AeroJudge Device image from:

   <https://aero-judge.com/device-images.php>

2. Use Raspberry Pi Imager to write the downloaded image to the SD card.

3. Insert the SD card into the AeroJudge Device and boot it.

4. Connect via ssh to the device as user `judge`, then run:

   ```sh
   cd /home/judge
   ./build_aerojudge.sh
   ```

    The `build_aerojudge.sh` launcher downloads and runs the current production 
    setup and asks for device-specific settings, installs the application and services,
    validates the result, and ends with a reboot command.

5. Then validate on assembled hardware:

   - AeroJudge opens at the First Boot - Event Setup Screen `newcomp.html` 
   - Score must be available, Set base event settings and Line/Judge numbers. 
   - Continue with "Load Event"

6. Test physical controls and functionality:
   - GPIO scoring buttons perform the expected actions
   - volume thumbwheel changes volume
   - audio is audible through the device amplifier
   - shutdown/poweroff behavior works


# Advanced details, settings, configurations and recovery options:

## Settings and hardware configuration

Settings are stored in `/var/opt/judge/settings.json`, not `/boot/settings.json`.
Use the app’s admin screens where available. For other settings, connect over
SSH as `judge`:

```sh
sudo vi /var/opt/judge/settings.json
```

| Setting | Default |
|---|---|
| `judge_id` | `1` |
| `line_number` | `1` |
| `score_host` | `192.168.8.100` |
| `score_http_port` | `80` |
| `language` | `en` |
| `score_poll_timeout` | `2` |
| `score_timeout` | `10` |
| `seasonYear` | Entered during setup |

The app release version does not select the figure season.

Setup uses `config/profiles/pcb-3.61/config.txt`. The stored 3.60 profile and
`config/profiles/archive/pcb-3.50/config.txt` do not enable automatic hardware
selection or expand supported hardware.

Board identity is provisioned once using `device_identity.sh`.
Remove the tool from the device after use.

## Diagnostics and version checks

Services, application health, and runtime files:

```sh
systemctl is-active judge.service kiosk.service audio-hardware.service volume.service
systemctl is-enabled judge.service kiosk.service audio-hardware.service volume.service
curl -s http://localhost:8080/actuator/health
ls -ld /var/opt/judge/pilots /var/opt/judge/pilots/scores
cat /var/opt/judge/settings.json
```

Audio hardware and logs:

```sh
amixer -c sndrpihifiberry get Digital
raspi-gpio get 8
pactl info | grep -E 'Server Name|Default Sink'
journalctl -u audio-hardware.service -u volume.service -n 80 --no-pager
```

The running version comes from the JAR manifest. The release marker records
the last successfully installed release; it is separate from the running version.

```sh
# Running application version
curl -s http://localhost:8080/api/version

# Last successfully installed release
cat /home/judge/.judge_last_release

# Installed JAR manifest
unzip -p /var/opt/judge/bin/judge.jar META-INF/MANIFEST.MF | grep Implementation-Version
```

## Setup actions and recovery

| Area | Actions |
|---|---|
| Prerequisites | Requires Bullseye, 32-bit, user `judge`, and no existing AeroJudge install state. |
| Inputs | Collects board identity and season year before installation; provisions PCB EEPROM identity. |
| Storage and packages | Expands the root filesystem, installs required packages, and creates settings and pilot/score directories. |
| Application and services | Installs release assets, `judge.service`, `kiosk.service`, and `fetch_update.sh`; installs and enables `audio-hardware.service` and `volume.service`. |
| Hardware and desktop | Installs boot configuration and wallpaper, hides the Wastebasket, and disables PackageKit update prompts. |
| Validation | Checks services, release/audio assets, runtime directories, and PCB 3.61+ boot configuration. |

After collecting inputs, setup runs without further input until the reboot
prompt. Successful validation removes `/home/judge/build_aerojudge.sh` and
`/home/judge/judge_setup.sh`, retains the setup log, and offers to reboot.

Failed installation or validation leaves the entry scripts available.
Recover by reimaging; do not bypass the fresh-install guards.

## Download sources

| Setting | Default | Supplies |
|---|---|---|
| `AEROJUDGE_SCRIPTS_RAW_BASE_URL` | `https://raw.githubusercontent.com/AeroJudge/device-scripts/main` | Setup/maintenance scripts, config profiles, wallpaper, legacy test data |
| `AEROJUDGE_RAW_BASE_URL` | `https://raw.githubusercontent.com/AeroJudge/aerojudge-device-app/main` | App and kiosk units/launchers |
| `AEROJUDGE_RELEASE_API_URL` | `https://api.github.com/repos/AeroJudge/aerojudge-device-app/releases/latest` | App release assets |

The app release supplies `judge.jar`, `figures.zip`, and `volume_service.zip`.
Release tags use `vYY.MAJOR.MINOR`, for example `v26.1.0`.

## Testing alternate sources

- Use a disposable fresh device.
- Unset or empty settings use the defaults above.
- Each override controls its own source; selecting an app branch does not select a scripts branch.
- Raw URLs identify repository/ref roots; do not append `/scripts`.
- Overrides apply to the current process and its children, not future sessions.

Set any optional app-source or release overrides **before running the launcher**:

```sh
# Optional: app services and launchers from another branch
export AEROJUDGE_RAW_BASE_URL="https://raw.githubusercontent.com/<owner>/aerojudge-device-app/refs/heads/<branch>"

# Optional: release assets from another repository
export AEROJUDGE_RELEASE_API_URL="https://api.github.com/repos/<owner>/<repo>/releases/latest"
```

To test a scripts branch, fetch and run its launcher:

```sh
cd /home/judge
export AEROJUDGE_SCRIPTS_RAW_BASE_URL="https://raw.githubusercontent.com/<owner>/device-scripts/refs/heads/<branch>"
curl -fsSL "$AEROJUDGE_SCRIPTS_RAW_BASE_URL/build_aerojudge.sh" -o build_aerojudge.sh
chmod +x build_aerojudge.sh
./build_aerojudge.sh
```
