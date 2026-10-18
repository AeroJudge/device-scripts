#!/bin/bash
#
# AeroJudge board identity tool.
#
# Reads or writes the board identity record held in the RV-3028 user EEPROM
# through the kernel nvmem interface. Nothing else writes that EEPROM.
#
# Usage, from the directory containing this script:
#   ./device_identity.sh read
#   sudo ./device_identity.sh write
#   sudo ./device_identity.sh write --override    # deliberate recovery only
#
# Record, ASCII, NUL terminated, zero padded to 43 bytes:
#   AJ1;<build mark>;<board revision>;<serial>
#
# Exit codes:
#   0  valid record read, or written and verified by read-back
#   1  usage error, or operator declined/cancelled
#   2  no identity record present
#   3  tagged but invalid, or unsupported format version
#   4  EEPROM interface missing, or read, write, or read-back failed

set -u

NVMEM="/sys/bus/nvmem/devices/rv3028_eeprom0/nvmem"
EEPROM_SIZE=43
FORMAT="AJ1"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

BUILD_MARK_RE='^[A-HJ-M][0-9]{2}$'
BOARD_REV_RE='^[0-9]{1,2}\.[0-9]{1,2}$'
SERIAL_RE='^[A-Z0-9-]{1,8}$'

# Set by read_eeprom.
HEX=""      # all 43 bytes as lowercase hex, no separators
RECORD=""   # ASCII text before the first NUL
STATUS=0    # 0 valid, 2 no record, 3 invalid/unsupported
REASON=""   # diagnostic for STATUS 3

usage() {
    echo "Usage: $0 read | write [--override]" >&2
    exit 1
}

cancel() {
    echo
    echo "Cancelled. EEPROM unchanged."
    exit 1
}

print_dump() {
    od -A x -t x1z -v -N "$EEPROM_SIZE" "$NVMEM"
}

# Reads the EEPROM and classifies the stored record. Returns 4 only when the
# interface is missing or the read itself fails; everything else is in STATUS.
read_eeprom() {
    if [ ! -e "$NVMEM" ]; then
        echo -e "${RED}EEPROM interface not found: $NVMEM${NC}" >&2
        echo -e "${RED}The RTC overlay (dtoverlay=i2c-rtc,rv3028) must be active. This tool does not load it.${NC}" >&2
        return 4
    fi

    HEX=$(od -An -v -tx1 -N "$EEPROM_SIZE" "$NVMEM" 2>/dev/null | tr -d ' \n')
    if [ ${#HEX} -ne $((EEPROM_SIZE * 2)) ]; then
        echo -e "${RED}EEPROM read failed: got ${#HEX} hex digits, expected $((EEPROM_SIZE * 2)).${NC}" >&2
        return 4
    fi

    RECORD=""
    STATUS=0
    REASON=""

    # No record unless the area starts with the AJ tag. Factory filler varies.
    if [ "${HEX:0:4}" != "414a" ]; then
        STATUS=2
        return 0
    fi

    local i byte terminated=0 nonprintable=0
    for ((i = 0; i < ${#HEX}; i += 2)); do
        byte="${HEX:i:2}"
        if [ "$byte" = "00" ]; then
            terminated=1
            break
        fi
        if [[ "$byte" < "20" || "$byte" > "7e" ]]; then
            nonprintable=1
            byte="3f"
        fi
        RECORD+=$(printf "\\x$byte")
    done

    if [ $terminated -eq 0 ]; then
        STATUS=3; REASON="no terminator within $EEPROM_SIZE bytes"
        return 0
    fi
    if [ $nonprintable -eq 1 ]; then
        STATUS=3; REASON="non-printable byte before terminator"
        return 0
    fi
    if [[ "$RECORD" != "$FORMAT;"* ]]; then
        STATUS=3
        if [[ "$RECORD" =~ ^AJ[^\;]*\; ]]; then
            REASON="unsupported format version '${RECORD%%;*}'; this tool reads $FORMAT only"
        else
            REASON="malformed format tag"
        fi
        return 0
    fi

    local fields
    IFS=';' read -r -a fields <<< "$RECORD"
    if [ ${#fields[@]} -ne 4 ]; then
        STATUS=3; REASON="expected 4 fields, found ${#fields[@]}"
        return 0
    fi
    [[ "${fields[1]}" =~ $BUILD_MARK_RE ]] || { STATUS=3; REASON="bad build mark '${fields[1]}'"; return 0; }
    [[ "${fields[2]}" =~ $BOARD_REV_RE ]] || { STATUS=3; REASON="bad board revision '${fields[2]}'"; return 0; }
    [[ "${fields[3]}" =~ $SERIAL_RE ]]    || { STATUS=3; REASON="bad serial '${fields[3]}'"; return 0; }
    return 0
}

do_read() {
    read_eeprom || exit $?
    case $STATUS in
        0)
            echo "$RECORD"
            exit 0
            ;;
        2)
            echo "No identity record present." >&2
            print_dump >&2
            exit 2
            ;;
        3)
            echo -e "${RED}Invalid identity record: $REASON${NC}" >&2
            print_dump >&2
            exit 3
            ;;
    esac
}

# ask VAR REGEX PROMPT: repeats until the entry matches; EOF cancels.
ask() {
    local var="$1" re="$2" text="$3" value
    while true; do
        read -r -p "$text: " value || cancel
        if [[ "$value" =~ $re ]]; then
            printf -v "$var" '%s' "$value"
            return
        fi
        echo "Invalid entry."
    done
}

do_write() {
    local override="$1"
    local board_rev build_mark serial record answer payload expected

    [ "$(id -u)" -eq 0 ] || { echo "write requires root: sudo $0 write" >&2; exit 1; }

    read_eeprom || exit $?
    echo "Current EEPROM contents ($EEPROM_SIZE bytes):"
    print_dump
    case $STATUS in
        0)
            echo -e "Stored identity: ${GREEN}$RECORD${NC}"
            if [ "$override" -eq 0 ]; then
                echo -e "${RED}Identity already present. EEPROM unchanged.${NC}"
                echo "Changing it requires: sudo $0 write --override"
                exit 0
            fi
            ;;
        2)
            echo "No identity record present."
            ;;
        3)
            echo -e "${RED}Invalid identity record: $REASON${NC}"
            if [ "$override" -eq 0 ]; then
                echo -e "${RED}EEPROM unchanged. Correcting it requires: sudo $0 write --override${NC}" >&2
                exit 3
            fi
            ;;
    esac

    trap cancel INT TERM

    echo
    echo "Build mark: month letter plus two-digit year, the month this record is first written."
    echo "  A Jan   B Feb   C Mar   D Apr   E May   F Jun"
    echo "  G Jul   H Aug   J Sep   K Oct   L Nov   M Dec"
    echo "  Example: K26 = October 2026"
    ask build_mark "$BUILD_MARK_RE" "Build mark"
    echo
    echo "Board revision: the digits after 'Board Rev:' on the PCB, exactly as printed. Example: 3.61"
    ask board_rev "$BOARD_REV_RE" "Board revision"
    echo
    echo "Serial: uppercase letters, digits, and hyphen, 1-8 characters. Example: DPG-110"
    echo "Enter NO-SN for an unattached board."
    ask serial "$SERIAL_RE" "Serial"

    record="$FORMAT;$build_mark;$board_rev;$serial"

    echo
    echo "Record format:   $FORMAT;(mark);(revision);(serial)"
    echo -e "Record to write: ${GREEN}$record${NC}"
    if [ "$override" -eq 1 ]; then
        echo -e "${RED}OVERRIDE: this replaces the EEPROM contents shown above.${NC}"
        read -r -p "Type I UNDERSTAND to proceed: " answer || cancel
        [ "$answer" = "I UNDERSTAND" ] || cancel
    else
        read -r -p "Write this record? [y/N] " answer || cancel
        case "$answer" in
            [Yy]|[Yy][Ee][Ss]) ;;
            *) cancel ;;
        esac
    fi

    # Full 43-byte payload: record, NUL terminator, zero padding.
    payload=$(mktemp) || { echo "Could not create temp file." >&2; exit 4; }
    trap 'rm -f "$payload"' EXIT
    printf '%s' "$record" > "$payload"
    head -c $((EEPROM_SIZE - ${#record})) /dev/zero >> "$payload"
    expected=$(od -An -v -tx1 "$payload" | tr -d ' \n')

    # Do not let Ctrl-C interrupt the EEPROM write itself.
    trap '' INT TERM
    if ! dd if="$payload" of="$NVMEM" bs="$EEPROM_SIZE" count=1 conv=notrunc status=none; then
        echo -e "${RED}EEPROM write failed. Run '$0 read' to inspect what is stored.${NC}" >&2
        exit 4
    fi

    read_eeprom || exit $?
    if [ "$HEX" != "$expected" ]; then
        echo -e "${RED}Read-back mismatch. Inspect and correct with: sudo $0 write --override${NC}" >&2
        echo "Expected: $expected" >&2
        echo "Read:     $HEX" >&2
        print_dump >&2
        exit 4
    fi

    echo -e "${GREEN}Identity written and verified: $RECORD${NC}"
    exit 0
}

case "${1:-}" in
    read)
        [ $# -eq 1 ] || usage
        do_read
        ;;
    write)
        if [ $# -eq 1 ]; then
            do_write 0
        elif [ $# -eq 2 ] && [ "$2" = "--override" ]; then
            do_write 1
        else
            usage
        fi
        ;;
    *)
        usage
        ;;
esac
