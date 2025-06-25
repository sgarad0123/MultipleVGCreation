#!/bin/bash
set -e

echo "🔧 Generating export-vars.sh..."

OUTPUT_FILE="export-vars.sh"
echo '#!/bin/bash' > "$OUTPUT_FILE"
echo "export ORG=\"${ORG}\"" >> "$OUTPUT_FILE"
echo "export PROJECT=\"${PROJECT}\"" >> "$OUTPUT_FILE"
echo "export AZURE_DEVOPS_PAT=\"${AZURE_DEVOPS_PAT}\"" >> "$OUTPUT_FILE"

# Export TRACKCOUNT
echo "export TRACKCOUNT=${TRACKCOUNT}" >> "$OUTPUT_FILE"

# Loop through each track
for ((i=1; i<=${TRACKCOUNT}; i++)); do
  for key in name type appid apptype; do
    VAR_NAME="track${i}_${key}"
    VALUE="${!VAR_NAME}"
    if [[ -z "$VALUE" ]]; then
      echo "❌ ERROR: Missing variables for track${i} ($key)"
      exit 1
    fi
    echo "export $VAR_NAME=\"$VALUE\"" >> "$OUTPUT_FILE"
  done
done

echo "✅ export-vars.sh created with:"
cat "$OUTPUT_FILE"
