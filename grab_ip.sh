#!/usr/bin/env bash
set -euo pipefail

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


if [ ! -d ${target_dir} ]
then
  mkdir ${target_dir}
fi

for file in ${domain_dir}/*.txt;
do
  domain_name=$(basename ${file%.txt})
  grab_ip_print_header "📊 RAPPORT DES IPs du domain : ${domain_name}"
  ips=$(while IFS=$'\n' read -r d; 
  do
    if [ -n "$d" ]
	then
      grab_ip_resolve_dns $d A
      grab_ip_resolve_dns $d AAAA
	fi
  done < ${file})

  # Append to file
  domain_ips_file=${target_dir}/${domain_name}_ips.txt
  nb_line=0
  if [ -f ${domain_ips_file} ]
  then 
	nb_line=$(wc -l < ${domain_ips_file})
	ips="${ips}
$(cat ${domain_ips_file})"
  fi
  
  
  echo "${ips}" | sort | uniq > ${domain_ips_file}
  nb_new_line=$(wc -l < ${domain_ips_file})
  if [[ ${nb_new_line} -ne ${nb_line} ]]
  then
    echo "$((nb_new_line - nb_line)) new IPs added"
  fi
  
done
