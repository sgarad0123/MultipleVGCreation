#!/bin/bash

set -e

ENV="$1"
APPID="$2"
TRACKNAME="$3"
TRACKTYPE="$4"

if [[ -z "$ENV" || -z "$APPID" || -z "$TRACKNAME" || -z "$TRACKTYPE" ]]; then
  echo "❌ ERROR: Missing input arguments"
  echo "Usage: ./create-multi-env-vgs.sh <ENV> <APPID> <TRACKNAME> <TRACKTYPE>"
  exit 1
fi

# Env variables expected to be passed or exported
ORG="${org:-${ORG}}"
PROJECT="${project:-${PROJECT}}"
PAT="${AZURE_DEVOPS_PAT}"

if [[ -z "$ORG" || -z "$PROJECT" || -z "$PAT" ]]; then
  echo "❌ ERROR: Missing ORG, PROJECT, or PAT"
  exit 1
fi

ENCODED_PAT=$(printf ":%s" "$PAT" | base64 | tr -d '\n')
AUTH_HEADER="Authorization: Basic $ENCODED_PAT"

# Get Project ID
PROJECT_API_URL="https://dev.azure.com/$ORG/_apis/projects/$PROJECT?api-version=7.1-preview.1"
PROJECT_ID=$(curl -s -H "$AUTH_HEADER" "$PROJECT_API_URL" | jq -r '.id')

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
  echo "❌ ERROR: Failed to fetch project ID"
  exit 1
fi

VG_NAME="${ENV}-${APPID}-${TRACKNAME}-VG"

# Skip if VG already exists
CHECK_VG_URL="https://dev.azure.com/$ORG/$PROJECT/_apis/distributedtask/variablegroups?groupName=$VG_NAME&api-version=7.1-preview.2"
EXISTS=$(curl -s -H "$AUTH_HEADER" "$CHECK_VG_URL" | jq -r '.value | length')

if [[ "$EXISTS" -gt 0 ]]; then
  echo "✅ Variable group $VG_NAME already exists. Skipping creation."
  exit 0
fi

# Lowercase ENV
ENV_LC=$(echo "$ENV" | awk '{print tolower($0)}')
TRACKTYPE_LC=$(echo "$TRACKTYPE" | awk '{print tolower($0)}')
TRACKNAME_LC=$(echo "$TRACKNAME" | awk '{print tolower($0)}')

# AppCriticality
if [[ "$TRACKTYPE_LC" == "web" ]]; then
  APP_CRITICALITY="bcweb"
elif [[ "$TRACKTYPE_LC" == "chatbot" ]]; then
  if [[ "$ENV" == "PROD" || "$ENV" == "DR" ]]; then
    APP_CRITICALITY="chatbotweb"
  else
    APP_CRITICALITY="chatbotweb"
  fi
else
  APP_CRITICALITY="bcapi"
fi

# Namespace
if [[ "$ENV" == "PROD" || "$ENV" == "DR" ]]; then
  NAMESPACE="$APP_CRITICALITY"
else
  if [[ "$TRACKTYPE_LC" == "web" ]]; then
    NAMESPACE="${ENV_LC}intweb-bc"
  elif [[ "$TRACKTYPE_LC" == "chatbot" ]]; then
    NAMESPACE="${ENV_LC}intweb-chatbot"
  else
    NAMESPACE="${ENV_LC}intapi-bc"
  fi
fi

# Secret name and image path
SECRET_NAME="${ENV}-${APPID}-${TRACKTYPE}-${TRACKNAME}-secret"
SECRET_NAME=$(echo "$SECRET_NAME" | tr '[:upper:]' '[:lower:]')
IMAGE_PATH="\$(ACRPath-NonProd)/\$(${APPID}-${TRACKNAME}-ACRRepositoryName)"

# Build variable group values
cat > variables.json <<EOF
{
  "MSI-Identitybinding": { "value": "default", "isSecret": false },
  "sys-AppCriticality": { "value": "${APP_CRITICALITY}", "isSecret": false },
  "sys-Namespace": { "value": "${NAMESPACE}", "isSecret": false },
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

URL="https://dev.azure.com/$ORG/$PROJECT/_apis/distributedtask/variablegroups?api-version=7.1-preview.2"
RESPONSE_FILE=$(mktemp)

echo "📦 Creating variable group: $VG_NAME"
echo "📌 AppCriticality: $APP_CRITICALITY"
echo "📌 Namespace: $NAMESPACE"
echo "📌 Secret: $SECRET_NAME"
echo "📌 Image Path: $IMAGE_PATH"

HTTP_CODE=$(curl --http1.1 -s -w "%{http_code}" -o "$RESPONSE_FILE" -X POST \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "$BODY" "$URL")

if [[ "$HTTP_CODE" -ge 400 || "$HTTP_CODE" -eq 000 ]]; then
  echo "❌ ERROR: Failed to create variable group $VG_NAME"
  cat "$RESPONSE_FILE"
else
  echo "✅ Successfully created variable group: $VG_NAME"
fi
