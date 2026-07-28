#!/usr/bin/env bash
# ==========================================================================
# setup-can.sh -- bring up can0 for the EBB42 Gen2 + Eddy Duo
# --------------------------------------------------------------------------
# The host CAN bridge is the Octopus running Klipper's "USB to CAN bus
# bridge (USBCAN)" firmware. When it is plugged in and the gs_usb driver
# binds it, the kernel exposes a "can0" network interface. This script
# configures and raises that interface. (A BTT U2C adapter, if you use one
# instead, exposes can0 the same way.)
#
# !! BITRATE: 1000000 (1M) MUST match the CAN speed compiled into the
#    Klipper/Katapult firmware on the EBB42 and the Eddy. If the firmware
#    was built for a different speed, change BITRATE here to match, or
#    nothing on the bus will answer.
#
# !! TERMINATION: the bus needs EXACTLY TWO 120R terminators:
#      1. the CAN-120R jumper on the EBB42 (set it), and
#      2. the terminator at the bridge (Octopus) end of the bus.
#    Zero, one, or three terminators = flaky or dead bus.
#
# Run this before starting Klipper (it is safe to re-run). To make the
# setup survive reboots, see the persistence instructions it prints.
# ==========================================================================
set -euo pipefail

IFACE="can0"
BITRATE="1000000"     # must match the firmware CAN speed (see header)
TXQUEUELEN="128"

# --- 1. Does can0 exist at all? -------------------------------------------
if ! ip link show "${IFACE}" >/dev/null 2>&1; then
    echo "ERROR: ${IFACE} does not exist." >&2
    echo "The CAN bridge (the Octopus USBCAN build) is either not plugged" >&2
    echo "in, or its driver (gs_usb) is not bound. Check with:" >&2
    echo "    lsusb            # look for the bridge device" >&2
    echo "    dmesg | tail     # look for gs_usb registering ${IFACE}" >&2
    exit 1
fi

# --- 2. Configure and raise the interface ---------------------------------
# Take it down first so 'type can bitrate' is accepted; ignore failure
# (it may already be down).
sudo ip link set "${IFACE}" down || true
sudo ip link set "${IFACE}" type can bitrate "${BITRATE}"
sudo ip link set "${IFACE}" txqueuelen "${TXQUEUELEN}"
sudo ip link set "${IFACE}" up

echo "${IFACE} is up: bitrate ${BITRATE}, txqueuelen ${TXQUEUELEN}"
echo
echo "Find the Octopus-bridge / EBB42 / Eddy UUIDs with:"
echo "    ~/klipper/scripts/canbus_query.py ${IFACE}"
echo "    (or ~/katapult/scripts/flashtool.py -q)"
echo
# --- 3. How to persist across reboots -------------------------------------
cat <<'EOF'
This setup is lost on reboot. Pick ONE way to persist it:

Option A: ifupdown (Debian/Raspberry Pi OS with /etc/network/interfaces)
  Create /etc/network/interfaces.d/can0 containing:

    allow-hotplug can0
    iface can0 can static
        bitrate 1000000
        up ip link set can0 txqueuelen 128

Option B: systemd-networkd
  Create /etc/systemd/network/25-can.network containing:

    [Match]
    Name=can0

    [CAN]
    BitRate=1M

    [Link]
    TransmitQueueLength=128

  then: sudo systemctl enable --now systemd-networkd

Either way the bitrate (1000000) must stay in sync with the firmware CAN
speed on the EBB42 and Eddy, and the bus must keep exactly two 120R
terminators (EBB CAN-120R jumper + the bridge end).
EOF
