#!/usr/bin/python3
"""AeroJudge device clock helper, installed as /usr/local/sbin/aerojudge-clock.

One privileged, dumb command for reading and setting device time. The judging
app calls it through sudo; nothing in Java detects clock hardware.

    aerojudge-clock status                        prints none | valid | invalid
    aerojudge-clock set <epoch-seconds>           system clock and RTC, prints ok <rtc-epoch>
    aerojudge-clock set-system-only <epoch-seconds>   system clock only, prints ok

Exit 0 on success. Exit 1 on failure with one reason line on stderr and nothing
on stdout. Exit 2 on a usage error. The caller passes the epoch already
corrected for its own elapsed time; this helper sets exactly what it is given.

Why Python: the device's hwclock cannot read the RTC invalid-time flag, and
shell cannot issue ioctls. The standard library can. Python 3 is already a
setup package. Target interpreter is Raspberry Pi OS Bullseye's Python 3.9.
"""

from __future__ import annotations

import calendar
import fcntl
import signal
import struct
import sys
import time
from pathlib import Path

# First token of /sys/class/rtc/rtcN/name. Grows when a new board is qualified.
# Keep in step with the discovery loop in clock_setup.sh.
ACCEPTED_DRIVERS = ('rtc-rv3028',)

# include/uapi/linux/rtc.h on 32-bit ARM. struct rtc_time is nine native ints.
RTC_RD_TIME = 0x80247009
RTC_SET_TIME = 0x4024700a
RTC_VL_READ = 0x80047013

USAGE = 'usage: aerojudge-clock status | set <epoch-seconds> | set-system-only <epoch-seconds>'


def find_rtc() -> str | None:
    # Scan every RTC so an onboard clock at rtc0 is never mistaken for ours.
    for name_file in sorted(Path('/sys/class/rtc').glob('rtc*/name')):
        if name_file.read_text().split()[0] in ACCEPTED_DRIVERS:
            return '/dev/' + name_file.parent.name
    return None


def rtc_read_epoch(device: str) -> int:
    with open(device, 'rb', buffering=0) as rtc:
        data = bytearray(36)
        fcntl.ioctl(rtc, RTC_RD_TIME, data, True)
    sec, minute, hour, mday, mon, year = struct.unpack('=9i', data)[:6]
    return calendar.timegm((year + 1900, mon + 1, mday, hour, minute, sec))


def rtc_write_epoch(device: str, epoch: int) -> None:
    # Kernel fields: month 0-11, year since 1900, weekday Sunday=0, yearday 0-365.
    tm = time.gmtime(epoch)
    data = struct.pack('=9i', tm.tm_sec, tm.tm_min, tm.tm_hour, tm.tm_mday,
                       tm.tm_mon - 1, tm.tm_year - 1900, (tm.tm_wday + 1) % 7,
                       tm.tm_yday - 1, 0)
    with open(device, 'r+b', buffering=0) as rtc:
        fcntl.ioctl(rtc, RTC_SET_TIME, data)


def rtc_invalid(device: str) -> bool:
    # Bit 0 of RTC_VL_READ is "data invalid": the chip lost power and its time.
    # The driver refuses RTC_RD_TIME while it is set, so status reads only this.
    with open(device, 'rb', buffering=0) as rtc:
        data = bytearray(4)
        fcntl.ioctl(rtc, RTC_VL_READ, data, True)
    return bool(struct.unpack('=I', data)[0] & 1)


def set_system(epoch: float) -> None:
    # clock_settime also marks the kernel clock unsynchronized, which stops the
    # kernel's own periodic copy of system time into the RTC.
    t0 = time.monotonic()
    time.clock_settime(time.CLOCK_REALTIME, epoch)
    now = time.time()
    t1 = time.monotonic()
    if abs(now - (epoch + (t1 - t0))) > 1.0:
        raise RuntimeError('system clock did not take')


def cmd_status() -> int:
    device = find_rtc()
    if device is None:
        print('none')
    else:
        print('invalid' if rtc_invalid(device) else 'valid')
    return 0


def cmd_set(epoch: float) -> int:
    device = find_rtc()
    if device is None:
        raise RuntimeError('no supported RTC')
    set_system(epoch)
    # The RTC holds whole seconds, so compare integers: a correct write reads
    # back within one second of the system clock sampled right after it.
    rtc_write_epoch(device, int(time.time()))
    readback = rtc_read_epoch(device)
    if abs(int(time.time()) - readback) > 1:
        raise RuntimeError('RTC readback mismatch: %d' % readback)
    if rtc_invalid(device):
        raise RuntimeError('RTC still reports invalid time')
    print('ok %d' % readback)
    return 0


def cmd_set_system_only(epoch: float) -> int:
    set_system(epoch)
    print('ok')
    return 0


def main(argv: list[str]) -> int:
    # Safeguard, not a guaranteed deadline: default action terminates the
    # process after five seconds unless a kernel operation is uninterruptible.
    signal.alarm(5)
    try:
        if argv == ['status']:
            return cmd_status()
        if len(argv) == 2 and argv[0] in ('set', 'set-system-only'):
            whole, dot, fraction = argv[1].partition('.')
            if whole.isdecimal() and (not dot or fraction.isdecimal()):
                epoch = float(argv[1])
                return cmd_set(epoch) if argv[0] == 'set' else cmd_set_system_only(epoch)
        print(USAGE, file=sys.stderr)
        return 2
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
