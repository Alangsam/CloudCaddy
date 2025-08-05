#!/bin/bash

set -e

usage() {
  cat <<EOF
CloudCaddy Installer

Usage: $0 [-m] [-s] [-help]

Options:
  -m    Configure multiple zone/record pairs
  -s    Also create wildcard *.zone CNAME pointing to the zone
  -help Show this message and exit
EOF
}

MULTI=false
STAR=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m) MULTI=true ;;
    -s) STAR=true ;;
    -help|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

echo "=== Cloudflare Dynamic DNS Installer (cloudcaddy) ==="

# === Step 1: Install dependencies ===
echo "[1/6] Installing dependencies..."
if command -v apt >/dev/null 2>&1; then
  sudo apt update && sudo apt install -y jq curl
elif command -v yum >/dev/null 2>&1; then
  sudo yum install -y jq curl
elif command -v brew >/dev/null 2>&1; then
  brew install jq curl
else
  echo "Unsupported OS: please install 'jq' and 'curl' manually."
  exit 1
fi

# === Step 2: Prompt for Cloudflare config ===
echo "[2/6] Collecting Cloudflare credentials..."
read -rp "Enter your Cloudflare API token: " CF_API_TOKEN
if $MULTI; then
  echo "Enter zone and record pairs (blank zone to finish):"
  ZONES=()
  RECORDS=()
  while true; do
    read -rp "Zone Name (e.g., example.com, blank to finish): " z
    [[ -z "$z" ]] && break
    read -rp "Record Name for $z (e.g., home.$z): " r
    ZONES+=("$z")
    RECORDS+=("$r")
  done
  if [[ ${#ZONES[@]} -eq 0 ]]; then
    echo "No zones provided."
    exit 1
  fi
else
  read -rp "Enter your Zone Name (e.g., example.com): " ZONE_NAME
  read -rp "Enter your Record Name (e.g., home.example.com): " RECORD_NAME
fi

# === Step 3: Write .env file ===
echo "[3/6] Creating .env configuration..."
if $MULTI; then
  ENV_CONTENT="CF_API_TOKEN=\"$CF_API_TOKEN\"\n"
  ENV_CONTENT+="ZONES=("
  for z in "${ZONES[@]}"; do ENV_CONTENT+="\"$z\" "; done
  ENV_CONTENT+=")\nRECORDS=("
  for r in "${RECORDS[@]}"; do ENV_CONTENT+="\"$r\" "; done
  ENV_CONTENT+=")\n"
else
  ENV_CONTENT=$(cat <<EOF
CF_API_TOKEN="$CF_API_TOKEN"
ZONE_NAME="$ZONE_NAME"
RECORD_NAME="$RECORD_NAME"
EOF
)
fi

if $STAR; then
  ENV_CONTENT+="WILDCARD=1\n"
else
  ENV_CONTENT+="WILDCARD=0\n"
fi

# === Step 4: Deploy script and env file ===
echo "[4/6] Deploying to /opt/cloudflare-ddns..."
sudo mkdir -p /opt/cloudflare-ddns
echo "$ENV_CONTENT" | sudo tee /opt/cloudflare-ddns/cf-ddns.env >/dev/null
sudo cp ddns.sh /opt/cloudflare-ddns/ddns.sh
sudo chmod 700 /opt/cloudflare-ddns
sudo chmod 700 /opt/cloudflare-ddns/ddns.sh
sudo chmod 600 /opt/cloudflare-ddns/cf-ddns.env

# === Step 5: Create systemd service and timer ===

echo "[5/6] Creating systemd service and timer..."

# cloudcaddy.service
sudo tee /etc/systemd/system/cloudcaddy.service >/dev/null <<EOF
[Unit]
Description=Update Cloudflare A record with current IP
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/cloudflare-ddns/ddns.sh
EOF

# cloudcaddy.timer
sudo tee /etc/systemd/system/cloudcaddy.timer >/dev/null <<EOF
[Unit]
Description=Run Cloudcaddy DDNS update every 5 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable --now cloudcaddy.timer

# === Step 6: Confirm
echo "[6/6] Setup complete. Verifying..."

sudo systemctl list-timers | grep cloudcaddy || echo "Timer not found."
echo "Run this to see logs:"
echo "  sudo journalctl -u cloudcaddy.service --no-pager"

echo "✅ All set! cloudcaddy will now update your Cloudflare DNS every 5 minutes."
