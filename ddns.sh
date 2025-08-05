#!/bin/bash

show_help() {
  cat <<'USAGE'
CloudCaddy Dynamic DNS updater

Usage: $0 [-help]

Reads configuration from /opt/cloudflare-ddns/cf-ddns.json and updates Cloudflare
A records to match the machine's current public IP. Configuration may specify a
single zone/record pair via "zone" and "record" fields or multiple pairs using
arrays "zones" and "records" of equal length. When "wildcard" is true in the
configuration, a wildcard CNAME ("*.zone") pointing to the zone is ensured for
each zone.

Options:
  -help    Display this message and exit
USAGE
}

if [[ "$1" == "-help" ]]; then
  show_help
  exit 0
fi

CONFIG_FILE="/opt/cloudflare-ddns/cf-ddns.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config file: $CONFIG_FILE"
  exit 1
fi

CF_API_TOKEN=$(jq -r '.cf_api_token // empty' "$CONFIG_FILE")
if [[ -z "$CF_API_TOKEN" ]]; then
  echo "cf_api_token missing from config"
  exit 1
fi

if jq -e '.zones and .records' "$CONFIG_FILE" >/dev/null; then
  mapfile -t zones < <(jq -r '.zones[]' "$CONFIG_FILE")
  mapfile -t records < <(jq -r '.records[]' "$CONFIG_FILE")
  if [[ ${#zones[@]} -ne ${#records[@]} ]]; then
    echo "zones and records arrays must be the same length"
    exit 1
  fi
else
  ZONE_NAME=$(jq -r '.zone // empty' "$CONFIG_FILE")
  RECORD_NAME=$(jq -r '.record // empty' "$CONFIG_FILE")
  if [[ -z "$ZONE_NAME" || -z "$RECORD_NAME" ]]; then
    echo "zone/record missing in config"
    exit 1
  fi
  zones=("$ZONE_NAME")
  records=("$RECORD_NAME")
fi

WILDCARD=$(jq -r '.wildcard // false' "$CONFIG_FILE")

ensure_wildcard() {
  local zone=$1
  local zone_id=$2
  local wildcard_name="*.${zone}"

  local info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?name=${wildcard_name}" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json")
  local id=$(echo "$info" | jq -r '.result[0].id')
  if [[ -z "$id" || "$id" == "null" ]]; then
    local data="{\"type\":\"CNAME\",\"name\":\"${wildcard_name}\",\"content\":\"${zone}\",\"ttl\":300,\"proxied\":false}"
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "$data" >/dev/null
    echo "Created wildcard CNAME for ${zone}"
  fi
}

CURRENT_IP=$(curl -s https://api.ipify.org)
if [[ -z "$CURRENT_IP" ]]; then
  echo "Failed to get public IP."
  exit 1
fi

echo "Current IP: $CURRENT_IP"

for i in "${!zones[@]}"; do
  ZONE_NAME=${zones[$i]}
  RECORD_NAME=${records[$i]}
  echo "Processing $RECORD_NAME in zone $ZONE_NAME"

  ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${ZONE_NAME}" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

  if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
    echo "Failed to fetch Zone ID for $ZONE_NAME"
    continue
  fi

  if [[ "$WILDCARD" == "true" ]]; then
    ensure_wildcard "$ZONE_NAME" "$ZONE_ID"
  fi

  RECORD_INFO=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${RECORD_NAME}" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json")
  RECORD_ID=$(echo "$RECORD_INFO" | jq -r '.result[0].id')
  RECORD_IP=$(echo "$RECORD_INFO" | jq -r '.result[0].content')

  if [[ -z "$RECORD_ID" || "$RECORD_ID" == "null" ]]; then
    echo "Failed to fetch DNS record for $RECORD_NAME"
    continue
  fi

  echo "Cloudflare IP: $RECORD_IP"

  if [[ "$CURRENT_IP" != "$RECORD_IP" ]]; then
    echo "Updating DNS record..."
    RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"${RECORD_NAME}\",\"content\":\"${CURRENT_IP}\",\"ttl\":300,\"proxied\":false}")
    SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
    if [[ "$SUCCESS" == "true" ]]; then
      echo "DNS record updated to $CURRENT_IP"
    else
      echo "Failed to update record:"
      echo "$RESPONSE" | jq .
    fi
  else
    echo "No update needed."
  fi

done
