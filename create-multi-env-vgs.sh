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

ORG="${org:-${ORG}}"
PROJECT="${project:-${PROJECT}}"
PAT="${AZURE_DEVOPS_PAT}"

if [[ -z "$ORG" || -z "$PROJECT" || -z "$PAT" ]]; then
  echo "❌ ERROR: Missing ORG, PROJECT, or PAT environment variables"
  exit 1
fi

ENCODED_PAT=$(printf ":%s" "$PAT" | base64 | tr -d '\n')
AUTH_HEADER="Authorization: Basic $ENCODED_PAT"

# Fetch Project ID
PROJECT_ID=$(curl -s -H "$AUTH_HEADER" \
  "https://dev.azure.com/$ORG/_apis/projects/$PROJECT?api-version=7.1-preview.1" | jq -r '.id')

if [[ "$PROJECT_ID" == "null" || -z "$PROJECT_ID" ]]; then
  echo "❌ ERROR: Failed to fetch project ID"
  exit 1
fi

VG_NAME="${ENV}-${APPID}-${TRACKNAME}-VG"

# Normalize values
ENV_LC=$(echo "$ENV" | tr '[:upper:]' '[:lower:]')
TRACKTYPE_LC=$(echo "$TRACKTYPE" | tr '[:upper:]' '[:lower:]')
APPTYPE_LC=$(echo "$APPTYPE" | tr '[:upper:]' '[:lower:]')
TRACKNAME_LC=$(echo "$TRACKNAME" | tr '[:upper:]' '[:lower:]')

# ─────────────────────────────────────────────
# Logic for sys-AppCriticality
case "$APPTYPE_LC" in
  chatbot)             APP_CRIT="chatbot" ;;
  wa)                  APP_CRIT="bcweb" ;;
  contractautweb)      APP_CRIT="contractauthweb" ;;
  contractautapi)      APP_CRIT="contractauthapi" ;;
  api|func|bj)         APP_CRIT="bcapi" ;;
  *)                   APP_CRIT="bcapi" ;;
esac

# ─────────────────────────────────────────────
# Logic for sys-Namespace
if [[ "$ENV" == "DEV" ]]; then
  NS="${ENV_LC}intapi-bc"
else
  if [[ "$APPTYPE_LC" == "chatbot" && "$TRACKTYPE_LC" == "wa" ]]; then
    case "$ENV" in
      PROD|DR) NS="chatbotweb" ;;
      *)       NS="${ENV_LC}web-bc" ;;
    esac
  elif [[ "$APPTYPE_LC" == "chatbot" ]]; then
    case "$ENV" in
      PROD|DR) NS="chatbotweb" ;;
      *)       NS="${ENV_LC}web-chatbot" ;;
    esac
  elif [[ "$APPTYPE_LC" == "wa" ]]; then
    NS="${ENV_LC}web-bc"
  else
    case "$ENV" in
      PROD|DR) NS="bcapi" ;;
      *)       NS="${ENV_LC}api-bc" ;;
    esac
  fi
fi

# ─────────────────────────────────────────────
# sys-SecretResourceName (all lowercase)
SECRET_NAME=$(echo "${ENV}-${APPID}-${TRACKTYPE}-${TRACKNAME}-secret" | tr '[:upper:]' '[:lower:]')

# sys-ImagePath
IMAGE_PATH="\$(ACRPath-NonProd)/\$(${APPID}-${TRACKNAME}-ACRRepositoryName)"

# ─────────────────────────────────────────────
# Build variable group JSON
cat > variables.json <<EOF
{
  "MSI-Identitybinding": { "value": "default", "isSecret": false },
  "sys-AppCriticality": { "value": "${APP_CRIT}", "isSecret": false },
  "sys-Namespace": { "value": "${NS}", "isSecret": false },
  "sys-SecretResourceName": { "value": "${SECRET_NAME}", "isSecret": false },
  "sys-ImagePath": { "value": "${IMAGE_PATH}", "isSecret": false }
}
EOF

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

# ─────────────────────────────────────────────
# Create Variable Group
URL="https://dev.azure.com/$ORG/$PROJECT/_apis/distributedtask/variablegroups?api-version=7.1-preview.2"
RESPONSE_FILE=$(mktemp)

echo "----------------------------------------"
echo "🔧 Creating Variable Group: $VG_NAME"
echo "📌 ACR Image Path: $IMAGE_PATH"
echo "📌 Namespace: $NS"
echo "📌 AppCriticality: $APP_CRIT"
echo "📌 Secret Resource Name: $SECRET_NAME"
echo "----------------------------------------"

HTTP_CODE=$(curl --http1.1 -s -w "%{http_code}" -o "$RESPONSE_FILE" -X POST \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "$BODY" "$URL")

if [[ "$HTTP_CODE" -ge 400 || "$HTTP_CODE" -eq 000 ]]; then
  echo "❌ ERROR: Failed to create variable group: $VG_NAME"
  cat "$RESPONSE_FILE"
  exit 1
else
  echo "✅ Successfully created variable group: $VG_NAME"
fi
