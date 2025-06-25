#!/bin/bash
set -e

ENV="$1"
APPID="$2"
TRACKNAME="$3"
TRACKTYPE="$4"
APPTYPE="$5"

if [[ -z "$ENV" || -z "$APPID" || -z "$TRACKNAME" || -z "$TRACKTYPE" || -z "$APPTYPE" ]]; then
  echo "❌ ERROR: Missing input arguments"
  echo "Usage: ./create-multi-env-vgs.sh <ENV> <APPID> <TRACKNAME> <TRACKTYPE> <APPTYPE>"
  exit 1
fi

ORG="${ORG}"
PROJECT="${PROJECT}"
PAT="${AZURE_DEVOPS_PAT}"

ENCODED_PAT=$(printf ":%s" "$PAT" | base64 | tr -d '\n')
AUTH_HEADER="Authorization: Basic $ENCODED_PAT"

# Get Project ID
PROJECT_ID=$(curl -s -H "$AUTH_HEADER" \
  "https://dev.azure.com/$ORG/_apis/projects/$PROJECT?api-version=7.1-preview.1" \
  | jq -r '.id')

VG_NAME="${ENV}-${APPID}-${TRACKNAME}-VG"

# AppCriticality Logic
case "$APPTYPE" in
  chatbot) CRIT="chatbot" ;;
  wa) CRIT="bcweb" ;;
  contractautweb) CRIT="contractauthweb" ;;
  contractautapi) CRIT="contractauthapi" ;;
  api|func|bj) CRIT="bcapi" ;;
  *) CRIT="bcapi" ;;
esac

# Namespace Logic
ENV_LC=$(echo "$ENV" | tr '[:upper:]' '[:lower:]')

if [[ "$APPTYPE" == "chatbot" && "$TRACKTYPE" == "wa" ]]; then
  if [[ "$ENV" =~ ^(PROD|DR)$ ]]; then
    NS="chatbotweb"
  else
    NS="${ENV_LC}web-bc"
  fi
elif [[ "$TRACKTYPE" == "wa" ]]; then
  if [[ "$ENV" =~ ^(PROD|DR)$ ]]; then
    NS="bcweb"
  else
    NS="${ENV_LC}web-bc"
  fi
elif [[ "$ENV" == "DEV" ]]; then
  NS="${ENV_LC}intapi-bc"
else
  NS="bcapi"
fi

# Secret Resource Name
SECRET_NAME=$(echo "${ENV}-${APPID}-${TRACKTYPE}-${TRACKNAME}-secret" | tr '[:upper:]' '[:lower:]')

# Image Path
IMAGE_PATH="\$(ACRPath-NonProd)/\$(${APPID}-${TRACKNAME}-ACRRepositoryName)"

# Final JSON
cat > variables.json <<EOF
{
  "MSI-Identitybinding": { "value": "default", "isSecret": false },
  "sys-AppCriticality": { "value": "${CRIT}", "isSecret": false },
  "sys-Namespace": { "value": "${NS}", "isSecret": false },
  "sys-SecretResourceName": { "value": "${SECRET_NAME}", "isSecret": false },
  "sys-ImagePath": { "value": "${IMAGE_PATH}", "isSecret": false }
}
EOF

# Create Variable Group
BODY=$(jq -n \
  --arg name "$VG_NAME" \
  --arg projectId "$PROJECT_ID" \
  --arg projectName "$PROJECT" \
  --slurpfile variables variables.json \
  '{
    type: "Vsts",
    name: $name,
    variables: $variables[0],
    variableGroupProjectReferences: [
      {
        projectReference: {
          id: $projectId,
          name: $projectName
        },
        name: $name
      }
    ]
  }')

RESPONSE_FILE=$(mktemp)
URL="https://dev.azure.com/$ORG/$PROJECT/_apis/distributedtask/variablegroups?api-version=7.1-preview.2"

echo "📦 Creating variable group: $VG_NAME"

HTTP_CODE=$(curl --http1.1 -s -w "%{http_code}" -o "$RESPONSE_FILE" -X POST \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "$BODY" "$URL")

if [[ "$HTTP_CODE" -ge 400 || "$HTTP_CODE" -eq 000 ]]; then
  echo "❌ Failed to create variable group $VG_NAME"
  cat "$RESPONSE_FILE"
else
  echo "✅ Successfully created variable group: $VG_NAME"
fi
