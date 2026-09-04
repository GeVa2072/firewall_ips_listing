#!/usr/bin/env bash
set -euo pipefail

retention=30
while [[ $# -gt 0 ]]; do
  case "$1" in
    --retention)
      [[ $# -ge 2 ]] || { echo "Error: --retention requires a value." >&2; exit 1; }
      retention="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: grab_ip.sh [--retention N]   (default: 30 days, 0 disables purge)"; exit 0 ;;
    *)
      echo "Error: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

# Get the absolute directory of the currently running script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the function file safely
if [ -f "$SCRIPT_DIR/core.func" ]; then
    source "$SCRIPT_DIR/core.func"
else
    echo "Error: core.func not found." >&2
    exit 1
fi

target_dir=$SCRIPT_DIR/target
domain_dir=$SCRIPT_DIR/domains

shopt -s nullglob

# Reference timestamp and purge cutoff (ISO 8601 UTC, lexicographically comparable)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [ "${retention}" -gt 0 ]; then
  CUTOFF=$(date -u -d "${retention} days ago" +%Y-%m-%dT%H:%M:%SZ)
else
  CUTOFF="1970-01-01T00:00:00Z"
fi

if [ ! -d "${target_dir}" ]
then
  mkdir "${target_dir}"
fi

for file in "${domain_dir}"/*.txt;
do
  domain_name=$(basename "${file%.txt}")
  grab_ip_print_header "📊 RAPPORT DES IPs du domain : ${domain_name}"

  # Resolve A (v4) and AAAA (v6) for each host, emit "ip<TAB>type" lines
  resolved_tsv=$(while IFS=$'\n' read -r d;
  do
    if [ -n "$d" ]
	then
      grab_ip_resolve_dns "$d" A    | while read -r ip; do printf '%s\tv4\n' "$ip"; done
      grab_ip_resolve_dns "$d" AAAA  | while read -r ip; do printf '%s\tv6\n' "$ip"; done
	fi
  done < "$file")

  if [ -n "$resolved_tsv" ]; then
    NEW_IPS="$resolved_tsv"
  else
    NEW_IPS=''
  fi

  domain_ips_file="${target_dir}/${domain_name}.json"
  if [ -f "$domain_ips_file" ]; then
    OLD_JSON=$(cat "$domain_ips_file")
  else
    OLD_JSON='{"ips":[]}'
  fi

  result=$(grab_ip_merge_json "$OLD_JSON" "$NEW_IPS" "$NOW" "$CUTOFF" "$domain_name")

  printf '%s\n' "$result" | jq 'del(._stats)' > "$domain_ips_file"

  read -r added purged total <<< "$(printf '%s\n' "$result" | jq -r '._stats | "\(.added) \(.purged) \(.total)"')"
  echo "${added} new IPs added, ${purged} purged (${retention}d retention), ${total} total"

done
