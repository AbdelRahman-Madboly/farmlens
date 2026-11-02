#!/usr/bin/env bash
# FarmLens node: one-screen health check. Run on the Pi when something does
# not work, and send the output to whoever is helping you.
#
#   ~/farmlens/node/rpi/status.sh
set -uo pipefail

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="$(sed -n 's/^API_PORT=//p' "$PROJ_DIR/.env" 2>/dev/null | head -1)"
PORT="${PORT:-8000}"

ok()   { printf '  \033[1;32mOK\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; }
note() { printf '       %s\n' "$*"; }

echo "FarmLens node status ($(date '+%Y-%m-%d %H:%M'))"
echo ""

# Code version
if [ -d "$PROJ_DIR/../../.git" ]; then
    ok "Code: $(git -C "$PROJ_DIR/../.." log -1 --format='%h %s (%cr)')"
else
    bad "Code: not a git checkout, run the setup command from the README"
fi

# Service
if systemctl is-active --quiet farmlens 2>/dev/null; then
    ok "Service farmlens is running (starts on boot: $(systemctl is-enabled farmlens 2>/dev/null))"
else
    bad "Service farmlens is not running. Try: sudo systemctl restart farmlens"
fi

# API
if STATUS="$(curl -fsS --max-time 3 "http://127.0.0.1:$PORT/api/status" 2>/dev/null)"; then
    ok "Node answers on port $PORT"
    note "$STATUS"
else
    bad "Node does not answer on port $PORT"
fi

# Camera
CAM="$(printf '%s' "${STATUS:-}" | sed -n 's/.*"camera_backend":"\([^"]*\)".*/\1/p')"
NOTE="$(printf '%s' "${STATUS:-}" | sed -n 's/.*"camera_note":"\([^"]*\)".*/\1/p')"
case "$CAM" in
    picamera2|opencv) ok "Camera: $CAM" ;;
    *)
        bad "Camera: ${CAM:-unknown} (simulated frames, no real camera in use)"
        [ -n "$NOTE" ] && note "Node says: $NOTE"
        # What the Pi camera stack itself sees
        LIST=""
        for t in rpicam-hello libcamera-hello; do
            command -v "$t" > /dev/null && { LIST="$("$t" --list-cameras 2>&1 | head -6)"; break; }
        done
        [ -n "$LIST" ] && { note "Camera list:"; printf '%s\n' "$LIST" | sed 's/^/         /'; }
        for f in /boot/firmware/config.txt /boot/config.txt; do
            [ -f "$f" ] && { note "Boot config ($f): $(grep -E '^[[:space:]]*(camera_auto_detect|start_x|dtoverlay=(ov|imx))' "$f" | tr '\n' ' ')"; break; }
        done
        id -nG | grep -qw video || note "User $(id -un) is not in the video group: sudo usermod -aG video $(id -un), then reboot"
        note "Fix: power off, reseat the ribbon (contacts facing the HDMI ports on a Pi 4), power on."
        note "The node looks for the camera at every start (CAMERA_BACKEND=auto)." ;;
esac

# Wi-Fi
if command -v nmcli >/dev/null; then
    ACTIVE="$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep -v ':lo$' | tr '\n' ' ')"
    if nmcli -t -f NAME connection show --active 2>/dev/null | grep -qx farmlens-hotspot; then
        ok "Wi-Fi: joined the hotspot ($(nmcli -g 802-11-wireless.ssid connection show farmlens-hotspot 2>/dev/null))"
    elif nmcli -t -f NAME connection show 2>/dev/null | grep -qx farmlens-hotspot; then
        bad "Wi-Fi: hotspot saved but not joined. Is the phone hotspot on? Active: ${ACTIVE:-none}"
        note "Hotspots the Pi can see now:"
        nmcli -t -f SSID,SIGNAL device wifi list 2>/dev/null | head -8 | sed 's/^/         /'
    else
        bad "Wi-Fi: no FarmLens hotspot saved. Run setup.sh --no-apt"
    fi
fi

# Addresses
IPS="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.' | tr '\n' ' ')"
note ""
note "Hostname : $(hostname).local"
note "Addresses: ${IPS:-none}"
note "Dashboard: http://$(hostname).local:$PORT"
echo ""
echo "Last log lines:"
journalctl -u farmlens -n 8 --no-pager 2>/dev/null | sed 's/^/  /' || true
