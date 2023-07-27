#!/bin/bash

# Debug
#set -x
set -Eeo pipefail

################################################################################
# Max num of servers/relays to add from both Anonymous DNSCrypt and ODoH
MAX_SERVERS=8
MAX_RELAYS=5
################################################################################

# Get a random number with smallest possible:$1 and largest possible:$2
get_random() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error calling get_random(), one or more args missing within: $(basename "$0")"
    exit
  elif [ "$1" -ge "$2" ] || [ 0 -gt "$1" ] || [ 1 -gt "$2" ]; then
    echo "Error in get_random(), one or more args are illegal or negative"
  fi
  # Use random var if it exists, othewise use uuid
  local MOD=$(($2-$1+1))
  local RAND
  if [ -n "$RANDOM" ]; then
    RAND="$RANDOM"
  else
    RAND="$(tr -cd '1-9' < /proc/sys/kernel/random/uuid | \
      head -c 1)$(tr -cd '0-9' < /proc/sys/kernel/random/uuid | head -c 4)"
  fi
  # Return random val
  echo "$((RAND % MOD + $1))"
}

# Removes any DoH (dns over https) servers from a passed list file (arg $1)
strip_doh() {
  # Local vars
  local FILE="$1"
  if [ -z "$FILE" ]; then
    echo "Error, no file name provided to strip_doh()"
    exit 1
  elif [ ! -f "$FILE" ]; then 
    echo "Error, missing file in strip_doh(): $FILE"
    exit 1
  else
    sed -i "/doh/d" "$FILE"
  fi
}

# Pass a link (arg $1) to a resolvers.md file, check for local copy of the file, download 
# if no local copy, parse, and write the new parsed list to another file (arg $2)
get_list() {
  local LINK="$1"
  local OUTPUT_LIST="$2"
  [ -n "$LINK" ] || (echo "Error, no link provided to get_list()"; exit 1)
  [ -n "$OUTPUT_LIST" ] || (echo "Error, no output file provided to get_list()"; exit 1)
  [ -f "$OUTPUT_LIST" ] && rm -f "$OUTPUT_LIST"
  # Get resolver markdown local file name
  MARKDOWN="${LINK##*/}"
  MARKDOWN="$LOCAL_RESOLVES_DIR/$MARKDOWN"
  # Download local files if no local copy exists
  if [ -f "$MARKDOWN" ] && [ "$(wc -l < "$MARKDOWN")" -gt 0 ]; then
    echo "Skipping download, found local version of: $(basename "$MARKDOWN")"
  else 
    rm -f "$MARKDOWN"
    echo "Downloading local copy of: $(basename "$MARKDOWN")"
    wget -q "$LINK" -O "$MARKDOWN" || (echo "Error downloading $(basename "$MARKDOWN"), check network connection"; exit 1)
  fi
  grep -F "##" < "$MARKDOWN" | grep -vF "ipv6" | cut -d " " -f 2 >> "$OUTPUT_LIST" || true
}

# Select a random subset of servers from a file (arg $1) and replace it with the subset
# Can limit the max number of servers in subset by pasing a number (arg $2)
get_subset() {
  local FILE="$1"
  [ -f "$FILE" ] || (echo "Error, file not found: $FILE"; exit 1)
  [ -n "$2" ] && MAX_NUM="$2"
  local TEMP_FILE
  TEMP_FILE=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  local NUM
  NUM=$(wc -l < "$FILE")
  local NUM_SELECT=$(get_random "1" "$NUM")
  if [[ -n "$MAX_NUM" ]] && [[ "$NUM_SELECT" -gt "$MAX_NUM" ]]; then
    NUM_SELECT="$MAX_NUM"
  fi
  for i in $(seq 1 "$NUM_SELECT"); do 
    SELECT=$(get_random "1" "$NUM")
    head -n "$SELECT" < "$FILE" | tail -n 1 >> "$TEMP_FILE"
  done
  sort "$TEMP_FILE" | uniq > "$FILE"
  rm -f "$TEMP_FILE"
}

# Returns a file name with a relay string from the input relay file (arg $1)
relay_string() {
  local RELAY_FILE="$1"
  [ -f "$RELAY_FILE" ] || (echo "Error, relay file not found: $RELAY_FILE"; exit 1)
  local OUTPUT="via=["
  while read -r LINE; do
    OUTPUT="$OUTPUT'$LINE', "
  done < "$RELAY_FILE"
  echo "${OUTPUT::-2}]"
}

# Loop to add to end of a file (arg $1) from a server file (arg $2) and optional relay file (arg $3)
loop_populate() {
  local TOML_FILE="$1"
  local SERVER_FILE="$2"
  local RELAY_FILE="$3"
  [ -f "$TOML_FILE" ] || (echo "Error, toml file not found: $TOML_FILE"; exit 1)
  [ -f "$SERVER_FILE" ] || (echo "Error, server file not found: $SERVER_FILE"; exit 1)
  local RELAY_STRING=""
  [ -f "$RELAY_FILE" ] && RELAY_STRING=$(relay_string "$RELAY_FILE")
  # TODO: Handle non-anonymous server subset better
  while read -r LINE; do
    if [ -n "$RELAY_STRING" ]; then
      echo "    { server_name='$LINE', $RELAY_STRING }," >> "$TOML_FILE"
    else
      echo "    { server_name='$LINE', via=['*'] }," >> "$TOML_FILE"
    fi
  done < "$SERVER_FILE"
  # Trim a comma from the line
  sed -i "$ s/.$//" "$TOML_FILE"
}

# Insert routes into a toml config (arg $1) from a server file (arg $2) and optional relay file (arg $3)
insert_routes() {
  local TOML_FILE="$1"
  local SERVER_FILE="$2"
  local RELAY_FILE="$3"
  [ -f "$TOML_FILE" ] || (echo "Error, toml file not found: $TOML_FILE"; exit 1)
  local RELAY_STRING=""
  # Get a subset of the file(s) and trim them
  if [ -f "$SERVER_FILE" ]; then
    get_subset "$SERVER_FILE" "$MAX_SERVERS"
  else
    echo "Error, server file not found: $SERVER_FILE"
    exit 1
  fi
  [ -f "$RELAY_FILE" ] && get_subset "$RELAY_FILE" "$MAX_RELAYS"
  # Cut the anonymized_dns section from the toml
  TOTAL_LINES=$(wc -l < "$TOML_FILE")
  ANON_SECTION_LINE=$(grep -nFm 1 "[anonymized_dns]" "$TOML_FILE" | cut -d ":" -f 1)
  TOML_TOP=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  head -n "$ANON_SECTION_LINE" < "$TOML_FILE" > "$TOML_TOP"
  TOML_BOTTOM=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  tail -n "$((TOTAL_LINES - ANON_SECTION_LINE))" < "$TOML_FILE" > "$TOML_BOTTOM"
  # Check for an existing routes section
  if ! grep -q '^routes' < "$TOML_BOTTOM"; then
    # If there is no route section, inject one
    echo "
routes = [" >> "$TOML_TOP"
    loop_populate "$TOML_TOP" "$SERVER_FILE" "$RELAY_FILE"
    echo "]" >> "$TOML_TOP"
  else
    # If there is alread a route section, add to it
    ROUTE_END_LINE=$(grep -nm 1 '^]' "$TOML_BOTTOM" | cut -d ":" -f 1)
    ROUTE_END_LINE="$((ROUTE_END_LINE + ANON_SECTION_LINE - 1))"
    # Create new top and bottom file
    head -n "$ROUTE_END_LINE" < "$TOML_FILE" > "$TOML_TOP"
    tail -n "$((TOTAL_LINES - ROUTE_END_LINE))" < "$TOML_FILE" > "$TOML_BOTTOM"
    # Add a comma to the line
    sed -i "$ s/$/,/" "$TOML_TOP"
    # Fill rest of data
    loop_populate "$TOML_TOP" "$SERVER_FILE" "$RELAY_FILE"
  fi
  # Splice together the final toml config
  mv "$TOML_TOP" "$TOML_FILE"
  cat "$TOML_BOTTOM" >> "$TOML_FILE"
  rm -f "$TOML_BOTTOM"
}

# Insert server_names into a toml config (arg $1) from a server file (arg $2)
insert_names() {
  local TOML_FILE="$1"
  local SERVER_FILE="$2"
  [ -f "$TOML_FILE" ] || (echo "Error, toml file not found: $TOML_FILE"; exit 1)
  # Get a subset of the file(s) and trim them
  if [ -f "$SERVER_FILE" ]; then
    get_subset "$SERVER_FILE" "$MAX_SERVERS"
  else
    echo "Error, server file not found: $SERVER_FILE"
    exit 1
  fi
  # Create server_names string
  SERVER_NAMES="server_names = ["
  while read -r LINE; do
    SERVER_NAMES="$SERVER_NAMES'$LINE', "
  done < "$SERVER_FILE"
  # Trim last 2 chars
  SERVER_NAMES="${SERVER_NAMES::-2}]"
  # Delete existing server_names if present
  sed -i '/^server_names = /d' "$TOML_FILE"
  sed -i '/^ server_names = /d' "$TOML_FILE"
  # Insert new server names into global settings
  TOTAL_LINES=$(wc -l < "$TOML_FILE")
  GLOBAL_SECTION_LINE=$(grep -nFm 1 "Global settings" "$TOML_FILE" | cut -d ":" -f 1)
  TOML_TOP=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  head -n "$((GLOBAL_SECTION_LINE + 1))" < "$TOML_FILE" > "$TOML_TOP"
  TOML_BOTTOM=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  tail -n "$((TOTAL_LINES - GLOBAL_SECTION_LINE - 1))" < "$TOML_FILE" > "$TOML_BOTTOM"
  echo "
$SERVER_NAMES" >> "$TOML_TOP"
  # Splice together the final toml config
  mv "$TOML_TOP" "$TOML_FILE"
  cat "$TOML_BOTTOM" >> "$TOML_FILE"
  rm -f "$TOML_BOTTOM"
}

# Enables ODoH in a toml file passed as arg $1
enable_odoh() {
  local TOML_FILE="$1"
  [ -f "$TOML_FILE" ] || (echo "Error, file not found: $TOML_FILE"; exit 1)
  # Enable odoh
  sed -i "s/odoh_servers = false/odoh_servers = true/g" "$TOML_FILE"
  # Get line to check for ODoH config
  TOTAL_LINES=$(wc -l < "$TOML_FILE")
  ODOH_LINE=$(grep -nFm 1 "### ODoH (Oblivious DoH) servers and relays" "$TOML_FILE" | cut -d ":" -f 1)
  # Splice in uncommented odoh config if it isn't already present 
  TEMP_TOML=$(mktemp /tmp/gen_dnscrypt.XXXXXX || exit 1)
  head -n "$ODOH_LINE" < "$TOML_FILE" > "$TEMP_TOML"
  if grep -qF "# [sources.odoh-servers]" < "$TOML_FILE" && ! grep -qF "  [sources.odoh-servers]" < "$TOML_FILE"; then
    echo "
  [sources.odoh-servers]
    urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/odoh-servers.md', 'https://download.dnscrypt.info/resolvers-list/v3/odoh-servers.md', 'https://ipv6.download.dnscrypt.info/resolvers-list/v3/odoh-servers.md']
    cache_file = 'odoh-servers.md'
    minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
    refresh_delay = 24
    prefix = ''" >> "$TEMP_TOML"
  fi
  if grep -qF "# [sources.odoh-relays]" < "$TOML_FILE" && ! grep -qF "  [sources.odoh-relays]" < "$TOML_FILE"; then
    echo "  [sources.odoh-relays]
    urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/odoh-relays.md', 'https://download.dnscrypt.info/resolvers-list/v3/odoh-relays.md', 'https://ipv6.download.dnscrypt.info/resolvers-list/v3/odoh-relays.md']
    cache_file = 'odoh-relays.md'
    minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
    refresh_delay = 24
    prefix = ''" >> "$TEMP_TOML"
  fi
  tail -n "$((TOTAL_LINES - ODOH_LINE))" < "$TOML_FILE" >> "$TEMP_TOML"
  mv "$TEMP_TOML" "$TOML_FILE"
}
