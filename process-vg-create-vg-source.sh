#!/bin/bash
set -e

PARAM_ENVIRONMENTS="$1"

if [[ ! -f ./export-vars.sh ]]; then
  echo "❌ export-vars.sh not found! Did export step fail?"
  exit 1
fi

# 🔁 Load exported track variables dynamically
source ./export-vars.sh

echo "🔁 Environments to process: $PARAM_ENVIRONMENTS"
IFS=',' read -ra ENV_LIST <<< "$PARAM_ENVIRONMENTS"

if [[ -z "$TRACKCOUNT" ]]; then
  echo "❌ ERROR: 'trackcount' not defined"
  exit 1
fi

echo "Found TRACKCOUNT=$TRACKCOUNT"

for ((i=1; i<=TRACKCOUNT; i++)); do
  trackname=$(eval echo "\$track${i}_name")
  tracktype=$(eval echo "\$track${i}_type")
  appid=$(eval echo "\$track${i}_appid")
  apptype=$(eval echo "\$track${i}_apptype")

  if [[ -z "$trackname" || -z "$tracktype" || -z "$appid" || -z "$apptype" ]]; then
    echo "❌ ERROR: Missing variables for track$i"
    continue
  fi

  echo "🧩 Track $i: name=$trackname, type=$tracktype, appid=$appid, apptype=$apptype"

  for env in "${ENV_LIST[@]}"; do
    echo "➡️ Creating variable group for $env - $appid - $trackname"
    ./create-multi-env-vgs.sh "$env" "$appid" "$trackname" "$tracktype" "$apptype"
  done
done
