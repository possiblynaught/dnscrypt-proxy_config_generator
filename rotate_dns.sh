#!/bin/bash

# Debug
#set -x
set -Eeo pipefail

################################################################################
# Every time this script runs, it will update the dns servers with new ones
################################################################################

# Save script dir
SCRIPT_DIR="$(dirname "$0")"

# Check for dnscrypt
INSTALL_DIRECTORY="/etc/dnscrypt-proxy"
[ -d "${INSTALL_DIRECTORY}2" ] && INSTALL_DIRECTORY="/etc/dnscrypt-proxy2"
INSTALL_CONFIG="$INSTALL_DIR/dnscrypt-proxy.toml"
if [ ! -f "$INSTALL_CONFIG" ]; then
  echo "Error, dnscrypt doesn't appear to be installed: $INSTALL_DIRECTORY"
  exit 1
fi

# Check for subscrpts
GEN_SCRIPT="$SCRIPT_DIR/generate_config.sh"
if [ ! -x "$GEN_SCRIPT" ]; then
  echo "Error, generate script not found: $GEN_SCRIPT"
  exit 1
fi

# Generate a new config
TEMP_CONFIG="/tmp/dnscrypt-proxy.toml"
"$GEN_SCRIPT" || true # TODO: Fix this

# Backup old and move new in
[ -s "$INSTALL_CONFIG" ] && mv "$INSTALL_CONFIG" "$INSTALL_CONFIG.old"
mv "$TEMP_CONFIG" "$INSTALL_CONFIG"

# Restart dnscrypt
if command -v systemctl &> /dev/null; then
  systemctl restart dnscrypt-proxy.service
fi
