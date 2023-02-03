#!/bin/bash

# Debug
#set -x
set -Eeo pipefail

# Save script dir
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

################################################################################
# Default file paths
TEMPLATE_TOML="$SCRIPT_DIR/example-dnscrypt-proxy.toml"
OUTPUT_TOML="/tmp/dnscrypt-proxy.toml"
# Max num of servers/relays to add from Anonymous DNSCrypt and ODoH
MAX_SERVERS=7
MAX_RELAYS=5
################################################################################

# Override default output file if a file path was passed as an arg
[ -n "$1" ] && OUTPUT_TOML="$1"

# Check for source toml
[ -f "$TEMPLATE_TOML" ] || (echo "Error, toml config template not found: $TEMPLATE_TOML"; exit 1)

# Function to download lists from a link in $1 and save to a file, $2
get_list() {
  LINK="$1"
  FILE="$2"
  [ -n "$LINK" ] || (echo "Error, no link provided"; exit 1)
  [ -f "$FILE" ] && rm -f "$FILE"
  TEMP_FILE=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  wget "$LINK" -O "$TEMP_FILE"
  # Simplify the list and delete ipv6 servers
  grep -F "##" < "$TEMP_FILE" | grep -vF "ipv6" | cut -d " " -f 2 >> "$FILE" || true
  rm -f "$TEMP_FILE"
}

# Download Anonymous DNSCrypt lists from github
CRYPT_SERVERS_LINK="https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
CRYPT_RELAYS_LINK="https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/relays.md"
CRYPT_SERVERS_FILE=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
CRYPT_RELAYS_FILE=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
get_list "$CRYPT_SERVERS_LINK" "$CRYPT_SERVERS_FILE"
get_list "$CRYPT_RELAYS_LINK" "$CRYPT_RELAYS_FILE"
# Strip any doh configs
sed -i "/doh/d" "$CRYPT_SERVERS_FILE"
sed -i "/doh/d" "$CRYPT_RELAYS_FILE"

# Download ODoH lists from github
ODOH_SERVERS_LINK="https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/odoh-servers.md"
ODOH_RELAYS_LINK="https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/odoh-relays.md"
ODOH_SERVERS_FILE=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
ODOH_RELAYS_FILE=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
get_list "$ODOH_SERVERS_LINK" "$ODOH_SERVERS_FILE"
get_list "$ODOH_RELAYS_LINK" "$ODOH_RELAYS_FILE"

# Create output file
cp "$TEMPLATE_TOML" "$OUTPUT_TOML"
# Disable doh and enable odoh
sed -i "s/doh_servers = true/doh_servers = false/g" "$OUTPUT_TOML"
sed -i "s/odoh_servers = false/odoh_servers = true/g" "$OUTPUT_TOML"
# Block ipv6, may collide with dnsmasq dnssec option
sed -i "s/block_ipv6 = false/block_ipv6 = true/g" "$OUTPUT_TOML"
# Skip incompatible resolvers
sed -i "s/skip_incompatible = false/skip_incompatible = true/g" "$OUTPUT_TOML"

# Get line to check for ODoH config
TOTAL_LINES=$(wc -l < "$OUTPUT_TOML")
ODOH_LINE=$(grep -nFm 1 "### ODoH (Oblivious DoH) servers and relays" "$OUTPUT_TOML" | cut -d ":" -f 1)
# Splice in uncommented odoh config if it isn't already present 
TEMP_TOML=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
head -n "$ODOH_LINE" < "$OUTPUT_TOML" > "$TEMP_TOML"
if grep -qF "# [sources.odoh-servers]" < "$OUTPUT_TOML"; then
  echo "
  [sources.odoh-servers]
    urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/odoh-servers.md', 'https://download.dnscrypt.info/resolvers-list/v3/odoh-servers.md', 'https://ipv6.download.dnscrypt.info/resolvers-list/v3/odoh-servers.md']
    cache_file = 'odoh-servers.md'
    minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
    refresh_delay = 24
    prefix = ''" >> "$TEMP_TOML"
fi
if grep -qF "# [sources.odoh-relays]" < "$OUTPUT_TOML"; then
  echo "  [sources.odoh-relays]
    urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/odoh-relays.md', 'https://download.dnscrypt.info/resolvers-list/v3/odoh-relays.md', 'https://ipv6.download.dnscrypt.info/resolvers-list/v3/odoh-relays.md']
    cache_file = 'odoh-relays.md'
    minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
    refresh_delay = 24
    prefix = ''" >> "$TEMP_TOML"
fi
tail -n "$((TOTAL_LINES - ODOH_LINE))" < "$OUTPUT_TOML" >> "$TEMP_TOML"
mv "$TEMP_TOML" "$OUTPUT_TOML"

# Function to select random subset of a file and replace the file with the subset
get_subset() {
  FILE="$1"
  [ -n "$2" ] && MAX_NUM="$2"
  [ -f "$FILE" ] || (echo "Error, file not found: $FILE"; exit 1)
  TEMP_FILE=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  NUM=$(wc -l < "$FILE")
  NUM_SELECT=$((RANDOM % NUM + 1))
  if [[ "$NUM_SELECT" -gt "$MAX_NUM" ]]; then
    NUM_SELECT="$MAX_NUM"
  fi
  for i in $(seq 1 $NUM_SELECT); do 
    SELECT=$((RANDOM % NUM + 1))
    head -n "$SELECT" < "$FILE" | tail -n 1 >> "$TEMP_FILE"
  done
  sort "$TEMP_FILE" | uniq > "$FILE"
  rm -f "$TEMP_FILE"
}

# Outputs a via=['relay... relay string meant to be stored in a variable
relay_string() {
  RELAY_FILE="$1"
  OUTPUT="via=["
  [ -f "$RELAY_FILE" ] || (echo "Error, relay file not found: $RELAY_FILE"; exit 1)
  while read -r LINE; do
    OUTPUT="$OUTPUT'$LINE', "
  done < "$RELAY_FILE"
  OUTPUT="${OUTPUT::-2}]"
  echo "$OUTPUT"
}

# Choose relays/servers
TOTAL_LINES=$(wc -l < "$OUTPUT_TOML")
CRYPT_LINE=$(grep -nFm 1 "[anonymized_dns]" "$OUTPUT_TOML" | cut -d ":" -f 1)
TEMP_TOML=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
head -n "$CRYPT_LINE" < "$OUTPUT_TOML" > "$TEMP_TOML"
echo "
routes = [" >> "$TEMP_TOML"
# Anonymous DNSCrypt
get_subset "$CRYPT_SERVERS_FILE" "$MAX_SERVERS"
get_subset "$CRYPT_RELAYS_FILE" "$MAX_RELAYS"
CRYPT_RELAY_STRING=$(relay_string "$CRYPT_RELAYS_FILE")
while read -r LINE; do
  echo "    { server_name='$LINE', $CRYPT_RELAY_STRING }," >> "$TEMP_TOML"
done < "$CRYPT_SERVERS_FILE"
# ODoH
get_subset "$ODOH_SERVERS_FILE" "$MAX_SERVERS"
get_subset "$ODOH_RELAYS_FILE" "$MAX_RELAYS"
ODOH_RELAY_STRING=$(relay_string "$ODOH_RELAYS_FILE")
while read -r LINE; do
  echo "    { server_name='$LINE', $ODOH_RELAY_STRING }," >> "$TEMP_TOML"
done < "$ODOH_SERVERS_FILE"
# Delete the last comma and replace file
sed -i "$ s/.$//" "$TEMP_TOML"
echo "]" >> "$TEMP_TOML"
tail -n "$((TOTAL_LINES - CRYPT_LINE))" < "$OUTPUT_TOML" >> "$TEMP_TOML"
mv "$TEMP_TOML" "$OUTPUT_TOML"

# Notify of completion
echo "
################################################################################
Done, created the new config file here: $OUTPUT_TOML

- DNSCrypt: Randomized $(wc -l < "$CRYPT_SERVERS_FILE") servers and $(wc -l < "$CRYPT_RELAYS_FILE") relays
- ODoH: Randomized $(wc -l < "$ODOH_SERVERS_FILE") servers and $(wc -l < "$ODOH_RELAYS_FILE") relays
- Used config template: $TEMPLATE_TOML
################################################################################"

# Delete temp files no longer needed
rm -f "$CRYPT_SERVERS_FILE"
rm -f "$CRYPT_RELAYS_FILE"
rm -f "$ODOH_SERVERS_FILE"
rm -f "$ODOH_RELAYS_FILE"
