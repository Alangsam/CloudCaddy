#!/bin/bash

set -e

echo "=== Cloudflare Dynamic DNS Installer ==="

# === Step 1: Install dependencies ===
echo "[1/5] Installing dependencies..."
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

# === Step 2: Prompt for global vars ===
echo "[2/5] Collecting Cloudflare credentials..."
read -rp "Enter your Cloudflare API token: " CF_API_TOKEN
read -rp "Enter your Zone Name (e.g., example.com): " ZONE_NAME
read -rp "Enter your Record Name (e.g., home.example.com): " RECORD_NAME

# === Step 3: Create the .env file content ===
ENV_PATH="./cf-ddns.env"
echo "[3/5] Creating env file..."
cat <<EOF > "$ENV_PATH"
CF_API_TOKEN="$CF_API_TOKEN"
ZONE_NAME="$ZONE_NAME"
RECORD_NAME="$RECORD_NAME"
EOF

# === Step 4: Create /opt directory and secure files ===
echo "[4/5] Deploying to /opt/cloudflare-ddns..."
sudo mkdir -p /opt/cloudflare-ddns
sudo cp ddns.sh "$ENV_PATH" /opt/cloudflare-ddns/
sudo chmod 700 /opt/cloudflare-ddns
sudo chmod 700 /opt/cloudflare-ddns/ddns.sh
sudo chmod 600 /opt/cloudflare-ddns/cf-ddns.env

# === Step 5: Test run ===
echo "[5/5] Testing script..."
sudo /opt/cloudflare-ddns/ddns.sh

echo "✅ Installation complete. A cron or systemd job can now automate it."
