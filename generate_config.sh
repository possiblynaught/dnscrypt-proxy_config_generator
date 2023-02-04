#!/bin/bash

# Debug
#set -x
set -Eeo pipefail

# Save script dir
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

################################################################################
# Default file paths
OUTPUT_TOML="/tmp/dnscrypt-proxy.toml"
TEMPLATE_TOML="$SCRIPT_DIR/example-dnscrypt-proxy.toml"
# Max num of servers/relays to add from Anonymous DNSCrypt and ODoH
MAX_SERVERS=8
MAX_RELAYS=5
################################################################################

# Check for special input options, uses Anon DNSCrypt and ODoH by default:
#   For Anonymous DNSCrypt only, run  ->  ./generate_config.sh --anon
#   For Oblivious DoH only, run       ->  ./generate_config.sh --odoh
#   For standard DNSCrypt, run        ->  ./generate_config.sh --crypt
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

# Load functions that will be used by the script
FUNCTION_FILE="$SCRIPT_DIR/functions.sh"
[ -x "$FUNCTION_FILE" ] || (echo "Error, script functions not found: $FUNCTION_FILE"; exit 1)
# shellcheck source=/dev/null
source "$FUNCTION_FILE"

# Check for source toml
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
  # Download Anonymous DNSCrypt lists from github
  ANON_SERVERS_FILE=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  ANON_RELAYS_FILE=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  get_anon_dnscrypt "$ANON_SERVERS_FILE" "$ANON_RELAYS_FILE"
  insert_routes "$OUTPUT_TOML" "$ANON_SERVERS_FILE" "$ANON_RELAYS_FILE"
fi

# Run if Oblivious DoH desired
if [ "$USE_ODOH" -eq 1 ]; then
  # Download ODoH lists from github
  ODOH_SERVERS_FILE=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  ODOH_RELAYS_FILE=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  get_odoh "$ODOH_SERVERS_FILE" "$ODOH_RELAYS_FILE"
  enable_odoh "$OUTPUT_TOML"
  insert_routes "$OUTPUT_TOML" "$ODOH_SERVERS_FILE" "$ODOH_RELAYS_FILE"
fi

# Run if standard (non-anonymous) DNSCrypt desired
if [ "$USE_CRYPT" -eq 1 ]; then
  CRYPT_SERVERS_FILE=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  get_standard_dnscrypt "$CRYPT_SERVERS_FILE"
  insert_names "$OUTPUT_TOML" "$CRYPT_SERVERS_FILE"
fi

# Notify of completion
echo "
--------------------------------------------------------------------------------
$(basename "$0") created the config file: $OUTPUT_TOML
"
[ "$USE_ANON" -eq 1 ] && echo "- Anon DNSCrypt: Randomized $(wc -l < "$ANON_SERVERS_FILE") servers and $(wc -l < "$ANON_RELAYS_FILE") relays"
[ "$USE_ODOH" -eq 1 ] && echo "- ODoH: Randomized $(wc -l < "$ODOH_SERVERS_FILE") servers and $(wc -l < "$ODOH_RELAYS_FILE") relays"
[ "$USE_CRYPT" -eq 1 ] && echo "- Standard (non-anon) DNSCrypt: Randomized $(wc -l < "$CRYPT_SERVERS_FILE") servers"
echo "- Used config template: $TEMPLATE_TOML
--------------------------------------------------------------------------------"

# Delete temp files no longer needed
[ "$USE_ANON" -eq 1 ] && rm -f "$ANON_SERVERS_FILE"; rm -f "$ANON_RELAYS_FILE"
[ "$USE_ODOH" -eq 1 ] && rm -f "$ODOH_SERVERS_FILE"; rm -f "$ODOH_RELAYS_FILE"
[ "$USE_CRYPT" -eq 1 ] && rm -f "$CRYPT_SERVERS_FILE"
