#!/bin/bash
#
# AeroJudge device clock policy.
#
# Installs the aerojudge-clock helper on every device. On a device with a
# supported RTC it also stops the operating system from touching the RTC on
# its own: systemd-timesyncd disabled, the kernel clock marked unsynchronized,
# fake-hwclock purged, timezone UTC. Afterwards only time from Score, applied
# through the helper, reaches the RTC. A device without a supported RTC keeps
# its existing clock behavior and gets the helper only.
#
# Usage:
#   sudo clock_setup.sh --staged <dir>      <dir> holds device_clock.py
#
# judge_update.sh runs this during every update with the staged files, so it
# is safe to repeat. Policy is applied and verified first and the helper is
# installed last. Once the RTC check has run, any failure removes the helper:
# the app then reports the clock as unavailable instead of trusting a
# half-applied policy. Recovery commands are in SETUP.md.

set -Eeuo pipefail

HELPER=/usr/local/sbin/aerojudge-clock
SUDO_RULE=/etc/sudoers.d/aerojudge-clock
STEP="preflight"
HELPER_GATED=false   # true once the RTC check has run; failures then remove the helper
RTC_PRESENT=false
SUDO_TMP=""

fail() {
    echo "Clock policy failed at $STEP: $*" >&2
    if [ "$HELPER_GATED" = true ]; then
        rm -f -- "$HELPER"
        echo "Removed $HELPER. The app reports the clock as unavailable until clock_setup.sh succeeds." >&2
    fi
    exit 1
}

# set -E makes command substitutions inherit this trap, so a command that may
# legitimately fail inside $( ) carries || true.
trap 'fail "unexpected failure at line $LINENO"' ERR
trap '[ -z "$SUDO_TMP" ] || rm -f -- "$SUDO_TMP"' EXIT

# ---- 1. Preflight: nothing on the device changes before this passes --------

[ "$(id -u)" = 0 ] || fail "run with sudo"
if [ "$#" -ne 2 ] || [ "$1" != --staged ]; then
    fail "usage: sudo clock_setup.sh --staged <dir>"
fi
STAGED="$2"
for tool in python3 systemctl timedatectl visudo install cmp dpkg-query apt-get; do
    command -v "$tool" >/dev/null || fail "required tool is missing: $tool"
done
[ -s "$STAGED/device_clock.py" ] || fail "staged helper is missing: $STAGED/device_clock.py"

# ---- 2. Staged helper must compile; an installed working helper stays ------

STEP="checking staged helper"
python3 -m py_compile "$STAGED/device_clock.py" || fail "device_clock.py does not compile"
# py_compile writes a root-owned __pycache__ into the judge-owned staging
# directory, which the updater could not remove later.
rm -rf -- "$STAGED/__pycache__"

# ---- 3. RTC discovery: same rule as ACCEPTED_DRIVERS in device_clock.py ----

STEP="detecting RTC"
for name_file in /sys/class/rtc/rtc*/name; do
    [ -e "$name_file" ] || continue
    case "$(cut -d' ' -f1 "$name_file")" in
        rtc-rv3028) RTC_PRESENT=true; break ;;
    esac
done
HELPER_GATED=true

# ---- 4. Operating-system policy, RTC devices only -------------------------

if [ "$RTC_PRESENT" = true ]; then
    # Purge, not remove: purge also drops the hourly cron conffile. Needs the
    # dpkg lock; setup masks PackageKit so it is normally free.
    STEP="removing fake-hwclock"
    if [ "$(dpkg-query -W -f='${Status}' fake-hwclock 2>/dev/null || true)" = "install ok installed" ]; then
        systemctl disable --now fake-hwclock
        apt-get purge -y fake-hwclock
    fi

    # timesyncd stays installed; it is only disabled.
    STEP="disabling systemd-timesyncd"
    if [ "$(systemctl is-enabled systemd-timesyncd.service 2>/dev/null || true)" != disabled ] \
        || systemctl is-active --quiet systemd-timesyncd.service; then
        systemctl disable --now systemd-timesyncd.service
    fi

    # Stopping timesyncd does not clear the kernel's synchronized flag, and
    # the kernel keeps copying system time into the RTC every 11 minutes for
    # up to about nine hours while it is set. Re-setting the clock to its own
    # value clears it now. No shell-visible value reports the flag, so this
    # runs unconditionally; it touches no storage and not the RTC.
    STEP="marking the kernel clock unsynchronized"
    python3 -c 'import time; time.clock_settime(time.CLOCK_REALTIME, time.clock_gettime(time.CLOCK_REALTIME))'

    STEP="setting timezone UTC"
    [ "$(timedatectl show -p Timezone --value)" = UTC ] || timedatectl set-timezone UTC

    STEP="verifying clock policy"
    case "$(systemctl show systemd-timesyncd.service -p ActiveState --value)" in
        inactive|failed) ;;
        *) fail "systemd-timesyncd is still active" ;;
    esac
    [ "$(systemctl is-enabled systemd-timesyncd.service 2>/dev/null || true)" = disabled ] \
        || fail "systemd-timesyncd is not disabled"
    [ "$(systemctl show systemd-timesyncd.service -p MainPID --value)" = 0 ] \
        || fail "systemd-timesyncd still has a process"
    [ "$(dpkg-query -W -f='${Status}' fake-hwclock 2>/dev/null || true)" != "install ok installed" ] \
        || fail "fake-hwclock is still installed"
    [ "$(timedatectl show -p Timezone --value)" = UTC ] || fail "timezone is not UTC"
else
    echo "No supported RTC. Clock policy not applied."
fi

# ---- 5. Sudoers rule: least privilege for the judge user -------------------

STEP="installing sudoers rule"
SUDO_TMP=$(mktemp)
cat > "$SUDO_TMP" <<'SUDOERS'
# The helper validates its arguments and never invokes a shell.
judge ALL=(root) NOPASSWD: /usr/local/sbin/aerojudge-clock status, /usr/local/sbin/aerojudge-clock set *, /usr/local/sbin/aerojudge-clock set-system-only *
SUDOERS
chmod 0440 "$SUDO_TMP"
visudo -cf "$SUDO_TMP" >/dev/null || fail "sudoers rule failed validation"
if [ ! -e "$SUDO_RULE" ] || ! cmp -s "$SUDO_TMP" "$SUDO_RULE"; then
    install -o root -g root -m 0440 "$SUDO_TMP" "$SUDO_RULE"
fi
visudo -cf /etc/sudoers >/dev/null || fail "/etc/sudoers failed validation with the rule installed"

# ---- 6. Helper, installed last: its presence means policy verified --------

STEP="installing helper"
if [ ! -e "$HELPER" ] || ! cmp -s "$STAGED/device_clock.py" "$HELPER"; then
    install -o root -g root -m 0755 "$STAGED/device_clock.py" "$HELPER"
fi

# ---- 7. Verify the real app-side invocation on the target interpreter ------

STEP="verifying helper"
[ -x "$HELPER" ] || fail "helper is not executable"
STATUS=$(sudo -u judge sudo -n "$HELPER" status 2>&1 || true)
if [ "$RTC_PRESENT" = true ]; then
    case "$STATUS" in
        valid|invalid) ;;
        *) fail "helper status returned '$STATUS'; expected valid or invalid" ;;
    esac
else
    [ "$STATUS" = none ] || fail "helper status returned '$STATUS'; expected none"
fi

echo "$STATUS"
exit 0
