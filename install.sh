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


# === Step 3: Write JSON file ===
echo "[3/6] Creating JSON configuration..."
if $MULTI; then
  zones_json=$(printf '%s\n' "${ZONES[@]}" | jq -R . | jq -s .)
  records_json=$(printf '%s\n' "${RECORDS[@]}" | jq -R . | jq -s .)
  CONFIG_JSON=$(jq -n --arg token "$CF_API_TOKEN" \
    --argjson zones "$zones_json" --argjson records "$records_json" \
    --arg wildcard "$STAR" '{cf_api_token:$token,zones:$zones,records:$records,wildcard:($wildcard=="true")}')
else
  CONFIG_JSON=$(jq -n --arg token "$CF_API_TOKEN" --arg zone "$ZONE_NAME" \
    --arg record "$RECORD_NAME" --arg wildcard "$STAR" \
    '{cf_api_token:$token,zone:$zone,record:$record,wildcard:($wildcard=="true")}')
fi

# === Step 4: Deploy script and config file ===
echo "[4/6] Deploying to /opt/cloudflare-ddns..."
sudo mkdir -p /opt/cloudflare-ddns
echo "$CONFIG_JSON" | sudo tee /opt/cloudflare-ddns/cf-ddns.json >/dev/null
sudo cp ddns.sh /opt/cloudflare-ddns/ddns.sh
sudo chmod 700 /opt/cloudflare-ddns
sudo chmod 700 /opt/cloudflare-ddns/ddns.sh
sudo chmod 600 /opt/cloudflare-ddns/cf-ddns.json

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
