#!/usr/bin/env bash
# Copyright (C) 2026 SpacemiT (Hangzhou) Technology Co. Ltd.
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

PROFILE=full
if (($#)); then
    if [[ $# != 2 || "$1" != --profile || ( "$2" != full && "$2" != static ) ]]; then
        echo "Usage: configure_can_linglong.sh [--profile full|static]" >&2
        exit 1
    fi
    PROFILE="$2"
fi

if ((EUID != 0)); then
    exec sudo --user root -- "$0" "$@"
fi

readonly CAN_BITRATE=1000000
readonly CAN_RESTART_MS=10
readonly CAN_TX_QUEUE_LEN=100
CAN_INTERFACES=(can0 can1 can2 can3 can4 can5)
[[ "$PROFILE" != static ]] || CAN_INTERFACES=(can2 can3)
readonly -a CAN_INTERFACES

# Use the same lock as the hardware driver before changing any bus state.
umask 077
exec 8>/tmp/linglong_hardware.lock
if ! flock --exclusive --nonblock 8; then
    echo "LingLong hardware is in use; refusing to reconfigure CAN." >&2
    exit 1
fi

DEADLINE=$((SECONDS + 30))
for INTERFACE in "${CAN_INTERFACES[@]}"; do
    until ip link show dev "$INTERFACE" >/dev/null 2>&1; do
        if ((SECONDS >= DEADLINE)); then
            echo "CAN interface not found: $INTERFACE" >&2
            exit 1
        fi
        sleep 0.2
    done
done

for INTERFACE in "${CAN_INTERFACES[@]}"; do
    ip link set dev "$INTERFACE" down
    ip link set dev "$INTERFACE" type can bitrate "$CAN_BITRATE" restart-ms "$CAN_RESTART_MS" fd off
    ip link set dev "$INTERFACE" txqueuelen "$CAN_TX_QUEUE_LEN"
    ip link set dev "$INTERFACE" up
    echo "$INTERFACE: 1000000 bit/s, restart 10 ms, tx queue 100"
done
