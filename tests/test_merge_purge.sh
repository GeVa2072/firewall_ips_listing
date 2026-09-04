#!/usr/bin/env bash
set -euo pipefail

# Get the directory of the repo root (core.func lives one level above tests/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source the function file safely
if [ -f "$SCRIPT_DIR/core.func" ]; then
    source "$SCRIPT_DIR/core.func"
else
    echo "Error: core.func not found." >&2
    exit 1
fi

# Fixed timestamps for deterministic tests
NOW="2026-09-04T10:00:00Z"
RECENT="2026-09-03T10:00:00Z"
OLD="2026-07-01T10:00:00Z"
CUTOFF_30D="2026-08-05T10:00:00Z"
CUTOFF_NONE="1970-01-01T00:00:00Z"

total=0
success=0
failed=0

assert_eq() {
  desc=$1
  actual=$2
  expected=$3
  total=$((total + 1))
  if [ "$actual" = "$expected" ]; then
    grab_ip_print_status_line "${desc}" "${actual}" "${GREEN}SUCCESS${NC}"
    success=$((success + 1))
  else
    grab_ip_print_status_line "${desc}" "got=${actual} want=${expected}" "${RED}FAILED ${NC}"
    failed=$((failed + 1))
  fi
}

merge() {
  grab_ip_merge_json "$1" "$2" "$3" "$4" "$5"
}


# --- Scenario 1: first run (empty old) ---
grab_ip_print_header "TEST 1 : Premier run (ancien vide)"
result=$(merge '{"ips":[]}' $'1.2.3.4\tv4\n2001:db8::1\tv6' "$NOW" "$CUTOFF_30D" "test")
assert_eq "Stats : added"  \
  "$(printf '%s' "$result" | jq -r '._stats.added')"  "2"
assert_eq "Stats : total"  \
  "$(printf '%s' "$result" | jq -r '._stats.total')"  "2"
assert_eq "Stats : purged" \
  "$(printf '%s' "$result" | jq -r '._stats.purged')" "0"
assert_eq "IP v4 presente" \
  "$(printf '%s' "$result" | jq -r '.ips[] | select(.type=="v4") | .ip')" "1.2.3.4"
assert_eq "IP v6 presente" \
  "$(printf '%s' "$result" | jq -r '.ips[] | select(.type=="v6") | .ip')" "2001:db8::1"
assert_eq "last_seen vaut NOW" \
  "$(printf '%s' "$result" | jq -r '.ips[0].last_seen')" "$NOW"


# --- Scenario 2: same IPs re-resolved -> last_seen refreshed, 0 added ---
grab_ip_print_header "TEST 2 : Merge - last_seen rafraichi, 0 ajout"
old='{"ips":[{"ip":"1.2.3.4","type":"v4","last_seen":"'"$RECENT"'"}]}'
result=$(merge "$old" $'1.2.3.4\tv4' "$NOW" "$CUTOFF_30D" "test")
assert_eq "Stats : added"  \
  "$(printf '%s' "$result" | jq -r '._stats.added')"  "0"
assert_eq "last_seen rafraichi" \
  "$(printf '%s' "$result" | jq -r '.ips[0].last_seen')" "$NOW"
assert_eq "Total conserve" \
  "$(printf '%s' "$result" | jq -r '._stats.total')" "1"


# --- Scenario 3: old IP not re-resolved -> kept with old last_seen ---
grab_ip_print_header "TEST 3 : IP absente du run - conservee"
old='{"ips":[{"ip":"1.2.3.4","type":"v4","last_seen":"'"$RECENT"'"},{"ip":"5.6.7.8","type":"v4","last_seen":"'"$RECENT"'"}]}'
result=$(merge "$old" $'1.2.3.4\tv4' "$NOW" "$CUTOFF_30D" "test")
assert_eq "Stats : added" \
  "$(printf '%s' "$result" | jq -r '._stats.added')"  "0"
assert_eq "Stats : total" \
  "$(printf '%s' "$result" | jq -r '._stats.total')" "2"
assert_eq "IP absente conservee" \
  "$(printf '%s' "$result" | jq -r '.ips[] | select(.ip=="5.6.7.8") | .ip')" "5.6.7.8"
assert_eq "last_seen non rafraichi pour IP absente" \
  "$(printf '%s' "$result" | jq -r '.ips[] | select(.ip=="5.6.7.8") | .last_seen')" "$RECENT"


# --- Scenario 4: purge IP older than cutoff ---
grab_ip_print_header "TEST 4 : Purge IP ancienne (cutoff 30j)"
old='{"ips":[{"ip":"1.2.3.4","type":"v4","last_seen":"'"$NOW"'"},{"ip":"9.9.9.9","type":"v4","last_seen":"'"$OLD"'"}]}'
result=$(merge "$old" $'1.2.3.4\tv4' "$NOW" "$CUTOFF_30D" "test")
assert_eq "Stats : purged" \
  "$(printf '%s' "$result" | jq -r '._stats.purged')" "1"
assert_eq "Stats : total" \
  "$(printf '%s' "$result" | jq -r '._stats.total')" "1"
assert_eq "IP ancienne purgee" \
  "$(printf '%s' "$result" | jq -r '[.ips[].ip] | index("9.9.9.9")')" "null"


# --- Scenario 5: retention 0 -> no purge ---
grab_ip_print_header "TEST 5 : retention 0 - pas de purge"
old='{"ips":[{"ip":"1.2.3.4","type":"v4","last_seen":"'"$NOW"'"},{"ip":"9.9.9.9","type":"v4","last_seen":"'"$OLD"'"}]}'
result=$(merge "$old" $'1.2.3.4\tv4' "$NOW" "$CUTOFF_NONE" "test")
assert_eq "Stats : purged" \
  "$(printf '%s' "$result" | jq -r '._stats.purged')" "0"
assert_eq "Stats : total" \
  "$(printf '%s' "$result" | jq -r '._stats.total')" "2"
assert_eq "IP ancienne conservee" \
  "$(printf '%s' "$result" | jq -r '.ips[] | select(.ip=="9.9.9.9") | .ip')" "9.9.9.9"


# --- Scenario 6: empty resolution -> only purge ---
grab_ip_print_header "TEST 6 : Aucune IP resolue - purge only"
old='{"ips":[{"ip":"1.2.3.4","type":"v4","last_seen":"'"$NOW"'"},{"ip":"9.9.9.9","type":"v4","last_seen":"'"$OLD"'"}]}'
result=$(merge "$old" '' "$NOW" "$CUTOFF_30D" "test")
assert_eq "Stats : added" \
  "$(printf '%s' "$result" | jq -r '._stats.added')" "0"
assert_eq "Stats : purged" \
  "$(printf '%s' "$result" | jq -r '._stats.purged')" "1"
assert_eq "IP recente conservee" \
  "$(printf '%s' "$result" | jq -r '.ips[] | select(.ip=="1.2.3.4") | .ip')" "1.2.3.4"


# --- Scenario 7: domain field set ---
grab_ip_print_header "TEST 7 : Champ domain"
result=$(merge '{"ips":[]}' $'1.2.3.4\tv4' "$NOW" "$CUTOFF_30D" "mydomain")
assert_eq "Domaine defini" \
  "$(printf '%s' "$result" | jq -r '.domain')" "mydomain"


# --- Scenario 8: re-resolved IP with old type stays consistent ---
grab_ip_print_header "TEST 8 : Type preserve pour IP re-resolue"
old='{"ips":[{"ip":"1.2.3.4","type":"v4","last_seen":"'"$OLD"'"}]}'
result=$(merge "$old" $'1.2.3.4\tv4' "$NOW" "$CUTOFF_30D" "test")
assert_eq "Type conserve" \
  "$(printf '%s' "$result" | jq -r '.ips[0].type')" "v4"

grab_ip_print_footer ${total} ${success} ${failed}
