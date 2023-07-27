#!/bin/bash

# Debug
#set -x
set -Eeo pipefail

# Save script dir
SCRIPT_DIR="$(dirname "$0")"
LOCAL_RESOLVES_DIRECTORY="/etc/dnscrypt-proxy"
[ ! -d "$LOCAL_RESOLVES_DIRECTORY" ] && LOCAL_RESOLVES_DIR="$SCRIPT_DIR/resolvers"

################################################################################
# Default file paths
OUTPUT_TOML="/tmp/dnscrypt-proxy.toml"
TEMPLATE_TOML="$SCRIPT_DIR/example-dnscrypt-proxy.toml"
################################################################################

# Check for special input options, uses Anon DNSCrypt and ODoH by default:
#   Default, Anonymous DNS and ODoH   ->  ./generate_config.sh
#   For Anonymous DNSCrypt only, run  ->  ./generate_config.sh --anon
#   For Oblivious DoH only, run       ->  ./generate_config.sh --odoh
#   For standard DNSCrypt, run        ->  ./generate_config.sh --crypt

# Handle args passed
if [[ "$1" == "--anon" ]]; then
  USE_ANON=1
  USE_ODOH=0
  USE_CRYPT=0
elif [[ "$1" == "--odoh" ]]; then
  USE_ANON=0
  USE_ODOH=1
  USE_CRYPT=0
elif [[ "$1" == "--crypt" ]]; then
  USE_ANON=0
  USE_ODOH=0
  USE_CRYPT=1
else
  USE_ANON=1
  USE_ODOH=1
  USE_CRYPT=0
fi

# Handle seperate template
[ -s "$2" ] && TEMPLATE_TOML="$2" 

# Load functions that will be used by the script
FUNCTION_FILE="$SCRIPT_DIR/functions.sh"
[ -x "$FUNCTION_FILE" ] || (echo "Error, script functions not found: $FUNCTION_FILE"; exit 1)
# shellcheck source=/dev/null
source "$FUNCTION_FILE"
# Prep local dnscrypt-resolve directory for offline md storage
mkdir -p "$LOCAL_RESOLVES_DIR"
if [ ! -d "$LOCAL_RESOLVES_DIR" ]; then
  echo "Error, local dnscrypt-resolve storeage dir missing, please create the dir:"
  echo "$LOCAL_RESOLVES_DIR"
  exit 1
fi

# Check for source toml and prep the output file
[ -f "$TEMPLATE_TOML" ] || (echo "Error, toml config template not found: $TEMPLATE_TOML"; exit 1)
# Create output file
cp "$TEMPLATE_TOML" "$OUTPUT_TOML"
# Disable doh
sed -i "s/doh_servers = true/doh_servers = false/g" "$OUTPUT_TOML"
# Block ipv6, may collide with dnsmasq dnssec option
sed -i "s/block_ipv6 = false/block_ipv6 = true/g" "$OUTPUT_TOML"
# Skip incompatible resolvers
sed -i "s/skip_incompatible = false/skip_incompatible = true/g" "$OUTPUT_TOML"

# Run if Anonymous DNSCrypt desired
if [ "$USE_ANON" -eq 1 ]; then
  # Anonymous DNS resolve links
  SERVER_LINK="https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
  RELAY_LINK="https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/relays.md"
  # Get parsed lists of servers/relays
  ANON_SERVER_LIST=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  ANON_RELAY_LIST=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  get_list "$SERVER_LINK" "$ANON_SERVER_LIST"
  get_list "$RELAY_LINK" "$ANON_RELAY_LIST"
  # Remove any DNS over HTTPS (DoH) servers
  strip_doh "$ANON_SERVER_LIST"
  strip_doh "$ANON_RELAY_LIST"
  # Insert random configs into toml config
  insert_routes "$OUTPUT_TOML" "$ANON_SERVER_LIST" "$ANON_RELAY_LIST"
fi

# Run if Oblivious DoH desired
if [ "$USE_ODOH" -eq 1 ]; then
  # ODoH resolve links
  SERVER_LINK="https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/odoh-servers.md"
  RELAY_LINK="https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/odoh-relays.md"
  # Get parsed lists of servers/relays
  ODOH_SERVER_LIST=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  ODOH_RELAY_LIST=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  get_list "$SERVER_LINK" "$ODOH_SERVER_LIST"
  get_list "$RELAY_LINK" "$ODOH_RELAY_LIST"
  # Specific ODoH toml tweaks
  enable_odoh "$OUTPUT_TOML"
  # Insert random configs into toml config
  insert_routes "$OUTPUT_TOML" "$ODOH_SERVER_LIST" "$ODOH_RELAY_LIST"
fi

# Run if standard (non-anonymous) DNSCrypt desired
if [ "$USE_CRYPT" -eq 1 ]; then
  # DNSCrypt resolve link
  SERVER_LINK="https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
  # Get parsed list of servers
  CRYPT_SERVER_LIST=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  get_list "$SERVER_LINK" "$CRYPT_SERVER_LIST"
  # Remove any DNS over HTTPS (DoH) servers
  strip_doh "$CRYPT_SERVER_LIST"
  # Specific DNSCrypt toml tweak to force DNSSEC
  sed -i "s/require_dnssec = false/require_dnssec = true/g" "$OUTPUT_TOML"
  # Insert random config into toml config
  insert_names "$OUTPUT_TOML" "$CRYPT_SERVER_LIST"
fi

# Notify of completion
echo "
--------------------------------------------------------------------------------
$(basename "$0") created the config file: $OUTPUT_TOML
"
[ "$USE_ANON" -eq 1 ] && echo "- Anon DNSCrypt: Randomized $(wc -l < "$ANON_SERVER_LIST") servers and $(wc -l < "$ANON_RELAY_LIST") relays"
[ "$USE_ODOH" -eq 1 ] && echo "- ODoH: Randomized $(wc -l < "$ODOH_SERVER_LIST") servers and $(wc -l < "$ODOH_RELAY_LIST") relays"
[ "$USE_CRYPT" -eq 1 ] && echo "- Standard (non-anon) DNSCrypt: Randomized $(wc -l < "$CRYPT_SERVER_LIST") servers"
echo "- Started with toml template:
  $TEMPLATE_TOML
- Copy of dnscrypt-resolve files stored locally, remove to force re-download: 
  rm -rf $LOCAL_RESOLVES_DIR/
--------------------------------------------------------------------------------"

# Delete temp files no longer needed
[ "$USE_ANON" -eq 1 ] && rm -f "$ANON_SERVER_LIST"; rm -f "$ANON_RELAY_LIST"
[ "$USE_ODOH" -eq 1 ] && rm -f "$ODOH_SERVER_LIST"; rm -f "$ODOH_RELAY_LIST"
[ "$USE_CRYPT" -eq 1 ] && rm -f "$CRYPT_SERVER_LIST"
