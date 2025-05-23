#!/bin/bash

echo "Installing dependencies..."
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

echo "Dependencies installed."
