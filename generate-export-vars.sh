#!/bin/bash

echo "🔧 Generating export-vars.sh..."

cat > export-vars.sh <<EOF
#!/bin/bash
export ORG="${ORG}"
export PROJECT="${PROJECT}"
export AZURE_DEVOPS_PAT="${AZURE_DEVOPS_PAT}"
export TRACKCOUNT=1
export track1_name="${track1_name}"
export track1_type="${track1_type}"
export track1_appid="${track1_appid}"
export track1_apptype="${track1_apptype}"
EOF

chmod +x export-vars.sh
echo "✅ export-vars.sh created"
