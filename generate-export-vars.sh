#!/bin/bash

echo "🔧 Generating export-vars.sh..."

# Create clean export file
echo '#!/bin/bash' > export-vars.sh
echo "export ORG=\"$ORG\"" >> export-vars.sh
echo "export PROJECT=\"$PROJECT\"" >> export-vars.sh
echo "export AZURE_DEVOPS_PAT=\"$AZURE_DEVOPS_PAT\"" >> export-vars.sh
echo "export TRACKCOUNT=$TRACKCOUNT" >> export-vars.sh
echo "" >> export-vars.sh
echo "# Dynamically export all trackN_* variables" >> export-vars.sh

for ((i=1; i<=TRACKCOUNT; i++)); do
  for key in name type appid apptype; do
    varname="track${i}_${key}"
    value="${!varname}"
    if [[ -z "$value" ]]; then
      echo "❌ ERROR: Missing variables for track$i ($key)"
      exit 1
    fi
    echo "export $varname=\"$value\"" >> export-vars.sh
  done
done

echo "✅ export-vars.sh created:"
cat export-vars.sh
