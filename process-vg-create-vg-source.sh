#!/bin/bash

set -e

echo "🔁 Environments to process: DEV, SIT, UAT, PT, PROD, DR"

if [[ -z "$trackcount" ]]; then
  echo "❌ ERROR: 'trackcount' not defined in vg-create-vg-source"
  exit 1
fi

echo "Found TRACKCOUNT=$trackcount"

for i in $(seq 1 "$trackcount"); do
  NAME_VAR="track${i}_name"
  TYPE_VAR="track${i}_type"
  APPID_VAR="track${i}_appid"
  APPTYPE_VAR="track${i}_apptype"

  TRACK_NAME="${!NAME_VAR}"
  TRACK_TYPE="${!TYPE_VAR}"
  APP_ID="${!APPID_VAR}"
  APP_TYPE="${!APPTYPE_VAR}"

  if [[ -z "$TRACK_NAME" || -z "$TRACK_TYPE" || -z "$APP_ID" || -z "$APP_TYPE" ]]; then
    echo "❌ ERROR: Missing input for track $i"
    continue
  fi

  echo "🧩 Track $i: name=${TRACK_NAME}, type=${TRACK_TYPE}, appid=${APP_ID}, apptype=${APP_TYPE}"

  for ENV in DEV SIT UAT PT PROD DR; do
    echo "➡️ Creating variable group for $ENV - $APP_ID - $TRACK_NAME"
    ./create-multi-env-vgs.sh "$ENV" "$APP_ID" "$TRACK_NAME" "$TRACK_TYPE" "$APP_TYPE"
  done
done
