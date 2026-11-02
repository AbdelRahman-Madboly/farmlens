#!/usr/bin/env bash
# =============================================================================
# FarmLens node: setup AND update for Raspberry Pi OS (Bookworm or newer)
# =============================================================================
# Safe to run as many times as you like. Each run:
#   1. pulls the latest code from GitHub
#   2. installs or updates system and Python packages
#   3. moves settings over from an older install, if there is one
#   4. finds the camera and writes .env
#   5. names the Pi "farmlens" so the app can find farmlens.local
#   6. saves the phone hotspot so the Pi joins it on every boot. By default
#      the hotspot is named FarmLens with password 00000000: set the phone's
#      hotspot to exactly that and nothing has to be typed on the Pi
#   7. installs a service that starts the node on every boot
#
# Usage (run as your normal user, not with sudo):
#   ./setup.sh                                  hotspot FarmLens / 00000000
#   ./setup.sh --ssid "My Phone" --password "secret123"
#   ./setup.sh --ask-wifi                       asks for the hotspot name/password
#   ./setup.sh --skip-wifi                      keep the current Wi-Fi setup
#
# Options:
#   --ssid NAME         phone hotspot name (default FarmLens)
#   --password PASS     phone hotspot password, 8+ characters (default 00000000)
#   --ask-wifi          ask for the hotspot name and password
#   --skip-wifi         do not touch Wi-Fi settings
#   --connect-now       switch to the hotspot right away (drops an SSH session
#                       that runs over the current Wi-Fi)
#   --country CC        Wi-Fi country code (default EG)
#   --hostname NAME     Pi hostname (default farmlens)
#   --camera MODE       auto (default), picamera2, opencv or mock
#   --no-pull           do not run git pull
#   --no-apt            skip apt (faster re-runs, offline)
# =============================================================================
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$PROJ_DIR/../.." && pwd)"
VENV="$PROJ_DIR/venv"
ENV_FILE="$PROJ_DIR/.env"
SERVICE=farmlens
UNIT="/etc/systemd/system/$SERVICE.service"
WIFI_CON="farmlens-hotspot"
PORT=8000

ORIG_ARGS=("$@")
# Default demo hotspot. The phone's hotspot must use this name and password.
DEFAULT_SSID="FarmLens"; DEFAULT_PASSWORD="00000000"
SSID=""; PASSWORD=""; SKIP_WIFI=0; CONNECT_NOW=0; ASK_WIFI=0
COUNTRY="EG"; NEW_HOSTNAME="farmlens"; CAMERA="auto"; DO_PULL=1; DO_APT=1

while [ $# -gt 0 ]; do
    case "$1" in
        --ssid)        SSID="${2:-}"; shift 2 ;;
        --password)    PASSWORD="${2:-}"; shift 2 ;;
        --skip-wifi)   SKIP_WIFI=1; shift ;;
        --connect-now) CONNECT_NOW=1; shift ;;
        --country)     COUNTRY="${2:-EG}"; shift 2 ;;
        --hostname)    NEW_HOSTNAME="${2:-farmlens}"; shift 2 ;;
        --camera)      CAMERA="${2:-auto}"; shift 2 ;;
        --no-pull)     DO_PULL=0; shift ;;
        --no-apt)      DO_APT=0; shift ;;
        --ask-wifi)    ASK_WIFI=1; shift ;;
        -h|--help)     sed -n '2,33p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)"; exit 1 ;;
    esac
done

bold() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }

# Read from the terminal even when this script is piped in (curl | bash).
# /dev/tty can exist without a terminal behind it (ssh without -t), so test
# that it really opens.
TTY_OK=0
if (exec < /dev/tty) 2>/dev/null; then TTY_OK=1; fi

ask() {
    local prompt="$1" var="$2" secret="${3:-0}" reply=""
    if [ "$TTY_OK" = 1 ]; then
        if [ "$secret" = 1 ]; then
            read -r -s -p "$prompt" reply < /dev/tty; echo
        else
            read -r -p "$prompt" reply < /dev/tty
        fi
    fi
    printf -v "$var" '%s' "$reply"
}

# Set KEY=VALUE in .env, replacing an existing line or appending one.
set_env() {
    local key="$1" value="$2"
    if grep -qE "^[#[:space:]]*${key}=" "$ENV_FILE"; then
        sed -i -E "s|^[#[:space:]]*${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

if [ "$(id -u)" = 0 ]; then
    echo "Run this as your normal user (for example pi), not with sudo."
    echo "The script calls sudo itself when it needs to."
    exit 1
fi
RUN_USER="$(id -un)"

echo ""
echo "FarmLens node setup"
info "Project : $PROJ_DIR"
info "User    : $RUN_USER"

# ── 1. Latest code ───────────────────────────────────────────────────────────
if [ "$DO_PULL" = 1 ] && [ -d "$REPO_DIR/.git" ]; then
    bold "1/8 Getting the latest code"
    if git -C "$REPO_DIR" pull --ff-only; then
        info "Code is up to date: $(git -C "$REPO_DIR" log -1 --format='%h %s')"
        # The pull may have changed this script; run the new version.
        if [ "${FARMLENS_REEXEC:-0}" != 1 ]; then
            export FARMLENS_REEXEC=1
            exec bash "$PROJ_DIR/setup.sh" "${ORIG_ARGS[@]}" --no-pull
        fi
    else
        warn "git pull failed (local changes or no internet). Continuing with the code already here."
    fi
else
    bold "1/8 Skipping git pull"
fi

# ── 2. Stop an older install and carry its settings over ─────────────────────
bold "2/8 Checking for an older install"
OLD_DIR=""
if [ -f "$UNIT" ]; then
    OLD_DIR="$(sed -n 's/^WorkingDirectory=//p' "$UNIT" | head -1)"
    info "Found the $SERVICE service (from $OLD_DIR), stopping it"
    sudo systemctl stop "$SERVICE" 2>/dev/null || true
fi
# Old locations: the service's folder, the old scp target, and a non-git
# ~/farmlens that bootstrap.sh moved aside.
for d in "$OLD_DIR" "$HOME/farmlens-rpi" "$HOME"/farmlens.old-*/node/rpi "$HOME"/farmlens.old-*; do
    [ -n "$d" ] && [ -d "$d" ] && [ "$(cd "$d" && pwd)" != "$PROJ_DIR" ] || continue
    if [ -f "$d/.env" ] && [ ! -f "$ENV_FILE" ]; then
        cp "$d/.env" "$ENV_FILE"; info "Copied settings from $d/.env"
    fi
    if [ -f "$d/farmlens.db" ] && [ ! -f "$PROJ_DIR/farmlens.db" ]; then
        cp "$d/farmlens.db" "$PROJ_DIR/farmlens.db"; info "Copied cycle history from $d"
    fi
    info "The old folder $d is left as it was. Delete it once this works."
done
[ -z "$OLD_DIR" ] && info "None found, this is a fresh install"

# ── 3. System packages ───────────────────────────────────────────────────────
if [ "$DO_APT" = 1 ]; then
    bold "3/8 Installing system packages (this can take a few minutes)"
    sudo apt-get update -qq
    sudo apt-get install -y -qq --no-install-recommends git python3-venv python3-pip python3-numpy \
        python3-opencv sqlite3 avahi-daemon curl ca-certificates
    # Camera stack. --no-install-recommends keeps desktop packages off a
    # Lite image. Missing on non-Pi machines, which is fine.
    sudo apt-get install -y -qq --no-install-recommends python3-picamera2 \
        || warn "python3-picamera2 not available, the Pi camera module will not work"
    sudo apt-get install -y -qq rpicam-apps 2>/dev/null \
        || sudo apt-get install -y -qq libcamera-apps 2>/dev/null || true
else
    bold "3/8 Skipping apt"
fi
sudo usermod -aG video "$RUN_USER" 2>/dev/null || true

# ── 4. Python environment ────────────────────────────────────────────────────
bold "4/8 Python environment"
# The venv must see the apt packages (picamera2, opencv). Rebuild an old venv
# that cannot.
if [ -d "$VENV" ] && ! grep -q "include-system-site-packages = true" "$VENV/pyvenv.cfg" 2>/dev/null; then
    info "Rebuilding the old venv so it can use the camera packages"
    rm -rf "$VENV"
fi
[ -d "$VENV" ] || python3 -m venv --system-site-packages "$VENV"
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet -r "$PROJ_DIR/requirements.txt"
"$VENV/bin/python" -c "import fastapi, uvicorn, cv2, numpy; print('    FastAPI', fastapi.__version__, '| OpenCV', cv2.__version__)"
mkdir -p "$PROJ_DIR/logs/images" "$PROJ_DIR/models"
rm -f "$PROJ_DIR/start.sh"   # left by the old installer, no longer used

# ── 5. Camera and .env ───────────────────────────────────────────────────────
bold "5/8 Camera and settings"
[ -f "$ENV_FILE" ] || { cp "$PROJ_DIR/.env.example" "$ENV_FILE"; info "Created .env"; }

detect_camera() {
    if "$VENV/bin/python" -c "
from picamera2 import Picamera2
import sys
sys.exit(0 if Picamera2.global_camera_info() else 1)" 2>/dev/null; then
        echo picamera2; return
    fi
    # /dev/video* also exists for the Pi's video codecs, so open and read.
    if "$VENV/bin/python" -c "
import cv2, sys
cap = cv2.VideoCapture(0)
ok = cap.isOpened() and cap.read()[0]
cap.release()
sys.exit(0 if ok else 1)" 2>/dev/null; then
        echo opencv; return
    fi
    echo mock
}

if [ "$CAMERA" = auto ]; then
    CAMERA="$(detect_camera)"
    case "$CAMERA" in
        picamera2) info "Found the Pi camera module (ribbon cable)" ;;
        opencv)    info "Found a USB webcam" ;;
        mock)      warn "No camera found. Using simulated frames. Check the ribbon cable, then run setup again." ;;
    esac
fi
set_env API_HOST 0.0.0.0
set_env API_PORT "$PORT"
set_env CAMERA_BACKEND "$CAMERA"
grep -qE '^SENSOR_MODE=' "$ENV_FILE" || set_env SENSOR_MODE mock
grep -qE '^AI_MODE=' "$ENV_FILE" || set_env AI_MODE mock
info "CAMERA_BACKEND=$CAMERA, API_HOST=0.0.0.0, port $PORT"

# ── 6. Hostname ──────────────────────────────────────────────────────────────
bold "6/8 Hostname"
CUR_HOST="$(hostname)"
if [ "$CUR_HOST" != "$NEW_HOSTNAME" ]; then
    if command -v raspi-config >/dev/null; then
        sudo raspi-config nonint do_hostname "$NEW_HOSTNAME"
    else
        sudo hostnamectl set-hostname "$NEW_HOSTNAME"
        sudo sed -i -E "s/^127\.0\.1\.1.*/127.0.1.1\t$NEW_HOSTNAME/" /etc/hosts \
            || warn "Could not update /etc/hosts; sudo may warn about the old name until reboot"
    fi
    sudo hostnamectl set-hostname "$NEW_HOSTNAME" 2>/dev/null || true
    info "Hostname changed from $CUR_HOST to $NEW_HOSTNAME"
else
    info "Hostname is already $NEW_HOSTNAME"
fi
sudo systemctl enable --now avahi-daemon >/dev/null 2>&1 || true
sudo systemctl restart avahi-daemon 2>/dev/null || true
info "The node answers at $NEW_HOSTNAME.local"

# ── 7. Phone hotspot ─────────────────────────────────────────────────────────
bold "7/8 Phone hotspot"
if [ "$SKIP_WIFI" = 1 ]; then
    info "Skipped (--skip-wifi)"
elif ! command -v nmcli >/dev/null; then
    warn "NetworkManager (nmcli) not found. Use Raspberry Pi OS Bookworm or newer, or set Wi-Fi with raspi-config."
else
    if [ -z "$SSID" ] && [ "$ASK_WIFI" = 1 ]; then
        EXISTING="$(nmcli -g 802-11-wireless.ssid connection show "$WIFI_CON" 2>/dev/null || true)"
        [ -n "$EXISTING" ] && info "Saved hotspot: $EXISTING (press Enter to keep it)"
        ask "    Phone hotspot name (SSID), Enter to skip: " SSID
    elif [ -z "$SSID" ]; then
        SSID="$DEFAULT_SSID"
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        info "Using the default hotspot: name \"$SSID\", password \"$PASSWORD\""
    fi
    if [ -n "$SSID" ]; then
        while [ -z "$PASSWORD" ] || [ "${#PASSWORD}" -lt 8 ]; do
            [ -n "$PASSWORD" ] && warn "The password must be at least 8 characters"
            ask "    Hotspot password: " PASSWORD 1
            [ "$TTY_OK" = 1 ] || { warn "No terminal to ask for the password. Use --password."; exit 1; }
        done
        if command -v raspi-config >/dev/null; then
            sudo raspi-config nonint do_wifi_country "$COUNTRY" || true
        fi
        sudo rfkill unblock wifi 2>/dev/null || true
        sudo nmcli radio wifi on
        sudo nmcli connection delete "$WIFI_CON" >/dev/null 2>&1 || true
        WIFI_IF="$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}')"
        WIFI_IF="${WIFI_IF:-wlan0}"
        # Priority 100 beats other saved networks, so on boot the Pi joins the
        # hotspot whenever it is on, and falls back to other Wi-Fi otherwise.
        sudo nmcli connection add type wifi con-name "$WIFI_CON" ifname "$WIFI_IF" \
            ssid "$SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$PASSWORD" \
            connection.autoconnect yes connection.autoconnect-priority 100 \
            connection.autoconnect-retries 0 ipv4.method auto ipv6.method auto >/dev/null
        info "Saved hotspot \"$SSID\" on $WIFI_IF. The Pi joins it on every boot."

        WIFI_STATE="$(nmcli -t -f DEVICE,STATE device | awk -F: -v d="$WIFI_IF" '$1==d{print $2}')"
        if [ "$CONNECT_NOW" = 1 ] || [ "$WIFI_STATE" != connected ]; then
            info "Connecting to \"$SSID\" now (the hotspot must be on)..."
            if sudo nmcli --wait 30 connection up "$WIFI_CON" >/dev/null 2>&1; then
                info "Connected to the hotspot"
            else
                warn "Could not connect now. Turn the hotspot on and reboot, or see Troubleshooting in node/rpi/README.md"
            fi
        else
            info "Wi-Fi is in use right now, so the Pi switches to the hotspot at the next reboot"
            info "(or run again with --connect-now)"
        fi
    elif [ -n "${EXISTING:-}" ]; then
        info "Kept the saved hotspot \"$EXISTING\""
    else
        info "Skipped, no hotspot name given"
    fi
fi

# ── 8. Service that starts on boot ───────────────────────────────────────────
bold "8/8 Boot service"
sudo tee "$UNIT" > /dev/null <<UNITEOF
[Unit]
Description=FarmLens node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$RUN_USER
SupplementaryGroups=video
WorkingDirectory=$PROJ_DIR
ExecStart=$VENV/bin/python $PROJ_DIR/main.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNITEOF
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE" >/dev/null 2>&1
sudo systemctl restart "$SERVICE"

info "Waiting for the node to answer..."
OK=0
for _ in $(seq 1 20); do
    if curl -fsS "http://127.0.0.1:$PORT/api/status" -o /tmp/farmlens-status.json 2>/dev/null; then OK=1; break; fi
    sleep 1
done

echo ""
if [ "$OK" = 1 ]; then
    printf '\033[1;32mFarmLens node is running.\033[0m\n'
    info "$(cat /tmp/farmlens-status.json)"
else
    printf '\033[1;31mThe node did not start. Last log lines:\033[0m\n'
    sudo journalctl -u "$SERVICE" -n 30 --no-pager || true
    exit 1
fi

IPS="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.' | tr '\n' ' ')"
cat <<DONE

  In the app      : open FarmLens, tap "Find my node"
  In a browser    : http://$NEW_HOSTNAME.local:$PORT   or   http://${IPS%% *}:$PORT
  Pi addresses    : ${IPS:-none yet}

  The node starts by itself on every boot and joins the phone hotspot when it is on.
  Update later    : run this same script again
  Health check    : $PROJ_DIR/status.sh
  Live logs       : journalctl -u $SERVICE -f
  Restart         : sudo systemctl restart $SERVICE

DONE
