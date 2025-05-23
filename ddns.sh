#!/bin/bash

# === Load configuration ===
ENV_FILE="/opt/cloudflare-ddns/cf-ddns.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing config file: $ENV_FILE"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

# === Check required variables ===
if [ -z "$CF_API_TOKEN" ] || [ -z "$ZONE_NAME" ] || [ -z "$RECORD_NAME" ]; then
  echo "One or more required environment variables are missing."
  exit 1
fi

# === Get current public IP ===
CURRENT_IP=$(curl -s https://api.ipify.org)
if [ -z "$CURRENT_IP" ]; then
  echo "Failed to get public IP."
  exit 1
fi
echo "Current IP: $CURRENT_IP"

# === Get Zone ID ===
ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${ZONE_NAME}" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

if [ "$ZONE_ID" == "null" ] || [ -z "$ZONE_ID" ]; then
  echo "Failed to fetch Zone ID for $ZONE_NAME"
  exit 1
fi

# === Get Record ID and current Cloudflare IP ===
RECORD_INFO=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${RECORD_NAME}" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json")

RECORD_ID=$(echo "$RECORD_INFO" | jq -r '.result[0].id')
RECORD_IP=$(echo "$RECORD_INFO" | jq -r '.result[0].content')

if [ -z "$RECORD_ID" ] || [ "$RECORD_ID" == "null" ]; then
  echo "Failed to fetch DNS record for $RECORD_NAME"
  exit 1
fi

echo "Cloudflare IP: $RECORD_IP"

# === Update if needed ===
if [ "$CURRENT_IP" != "$RECORD_IP" ]; then
  echo "Updating DNS record..."
  RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"${RECORD_NAME}\",\"content\":\"${CURRENT_IP}\",\"ttl\":300,\"proxied\":false}")

  SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
  if [ "$SUCCESS" == "true" ]; then
    echo "DNS record updated to $CURRENT_IP"
  else
    echo "Failed to update record:"
    echo "$RESPONSE" | jq .
    exit 1
  fi
else
  echo "No update needed."
fi
