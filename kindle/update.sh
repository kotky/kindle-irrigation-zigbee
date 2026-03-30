#!/bin/sh
# Kindle dashboard updater
# Deploy to Kindle via SSH after jailbreak: scp kindle/update.sh root@kindle:/mnt/us/
# Run as: sh /mnt/us/update.sh &
#
# Requirements on Kindle:
#   - Jailbreak + USBNetwork or WiFi SSH access
#   - eips available (standard on Kindle Linux)
#   - wget available (busybox wget — no curl needed)
#
# Kindle Paperwhite screen: 600x800 pixels, 8-bit grayscale PNG.
# The puppet service on port 10000 returns a screenshot of the HA Lovelace
# 'kindle' dashboard view, automatically converted to the right format.

# ── Configuration ─────────────────────────────────────────────────────────────
# Replace with the LAN IP of the machine running docker compose.
SERVER_IP="192.168.1.100"

# Puppet screenshot URL — adjust viewport if your Kindle model differs:
#   Paperwhite 1/2/3: 600x800
#   Paperwhite 4/5/Signature: 1072x1448  (higher DPI, scale down in HA theme)
#   Oasis: 1264x1680
PUPPET_URL="http://${SERVER_IP}:10000/?url=/lovelace/kindle&viewport=600x800&colors=2bit-dithered"

TMP_PNG="/tmp/irrigation_dashboard.png"
INTERVAL=90   # seconds between refreshes

# ── Main loop ─────────────────────────────────────────────────────────────────
echo "[update.sh] Starting Kindle dashboard updater (interval: ${INTERVAL}s)"
echo "[update.sh] Fetching from: ${PUPPET_URL}"

while true; do
    if wget -q -O "${TMP_PNG}" "${PUPPET_URL}" 2>/dev/null; then
        eips -c                   # clear screen (prevents ghosting)
        eips -g "${TMP_PNG}"      # display PNG
        echo "[update.sh] Dashboard updated at $(date)"
    else
        echo "[update.sh] WARNING: Failed to download dashboard — will retry" >&2
    fi
    sleep "${INTERVAL}"
done
