#!/bin/bash
set -e

ENV_CSV="$1"
IFS=',' read -ra ENVIRONMENTS <<< "$ENV_CSV"

if [[ -z "$TRACKCOUNT" ]]; then
  echo "❌ ERROR: TRACKCOUNT not defined"
  exit 1
fi

if [[ ! -f ./export-vars.sh ]]; then
  echo "❌ ERROR: export-vars.sh not found"
  exit 1
fi

source ./export-vars.sh

echo "🔁 Environments to process: $ENV_CSV"
echo "Found TRACKCOUNT=$TRACKCOUNT"

for ((i=1; i<=TRACKCOUNT; i++)); do
  name_var="track${i}_name"
  type_var="track${i}_type"
  appid_var="track${i}_appid"
  apptype_var="track${i}_apptype"

  trackname="${!name_var}"
  tracktype="${!type_var}"
  appid="${!appid_var}"
  apptype="${!apptype_var}"

  if [[ -z "$trackname" || -z "$tracktype" || -z "$appid" || -z "$apptype" ]]; then
    echo "❌ ERROR: Missing variables for track$i"
    continue
  fi

  echo "🧩 Track $i: name=$trackname, type=$tracktype, appid=$appid, apptype=$apptype"

  for env in "${ENVIRONMENTS[@]}"; do
    echo "➡️ Creating variable group for $env - $appid - $trackname"
    ./create-multi-env-vgs.sh "$env" "$appid" "$trackname" "$tracktype" "$apptype"
  done
done
