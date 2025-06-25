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
  echo "❌ ERROR: Missing ORG, PROJECT, or PAT"
  exit 1
fi

ENCODED_PAT=$(printf ":%s" "$PAT" | base64 | tr -d '\n')
AUTH_HEADER="Authorization: Basic $ENCODED_PAT"

# Get Project ID
PROJECT_ID=$(curl -s -H "$AUTH_HEADER" \
  "https://dev.azure.com/$ORG/_apis/projects/$PROJECT?api-version=7.1-preview.1" | jq -r '.id')

if [[ "$PROJECT_ID" == "null" || -z "$PROJECT_ID" ]]; then
  echo "❌ ERROR: Failed to fetch project ID"
  exit 1
fi

VG_NAME="${ENV}-${APPID}-${TRACKNAME}-VG"
VG_CHECK_URL="https://dev.azure.com/$ORG/$PROJECT/_apis/distributedtask/variablegroups?groupName=$VG_NAME&api-version=7.1-preview.2"
VG_EXISTS=$(curl -s -H "$AUTH_HEADER" "$VG_CHECK_URL" | jq -r '.value | length')

if [[ "$VG_EXISTS" -gt 0 ]]; then
  echo "✅ Variable group $VG_NAME already exists. Skipping..."
  exit 0
fi

# Normalize input
ENV_LC=$(echo "$ENV" | tr '[:upper:]' '[:lower:]')
TRACKTYPE_LC=$(echo "$TRACKTYPE" | tr '[:upper:]' '[:lower:]')
APPTYPE_LC=$(echo "$APPTYPE" | tr '[:upper:]' '[:lower:]')
TRACKNAME_LC=$(echo "$TRACKNAME" | tr '[:upper:]' '[:lower:]')

# sys-AppCriticality
case "$APPTYPE_LC" in
  chatbot)            APP_CRITICALITY="chatbot" ;;
  wa)                 APP_CRITICALITY="bcweb" ;;
  contractautweb)     APP_CRITICALITY="contractauthweb" ;;
  contractautapi)     APP_CRITICALITY="contractauthapi" ;;
  api|func|bj)        APP_CRITICALITY="bcapi" ;;
  *)                  APP_CRITICALITY="bcapi" ;;
esac

# sys-Namespace
if [[ "$ENV" == "DEV" ]]; then
  NAMESPACE="${ENV_LC}intapi-bc"
else
  if [[ "$APPTYPE_LC" == "chatbot" && "$TRACKTYPE_LC" == "wa" ]]; then
    case "$ENV" in
      PROD|DR) NAMESPACE="chatbotweb" ;;
      *)       NAMESPACE="${ENV_LC}web-bc" ;;
    esac
  elif [[ "$APPTYPE_LC" == "chatbot" ]]; then
    case "$ENV" in
      PROD|DR) NAMESPACE="chatbotweb" ;;
      *)       NAMESPACE="${ENV_LC}web-chatbot" ;;
    esac
  elif [[ "$APPTYPE_LC" == "wa" ]]; then
    NAMESPACE="${ENV_LC}web-bc"
  else
    case "$ENV" in
      PROD|DR) NAMESPACE="bcapi" ;;
      *)       NAMESPACE="${ENV_LC}api-bc" ;;
    esac
  fi
fi

# sys-SecretResourceName
SECRET_NAME=$(echo "${ENV}-${APPID}-${TRACKTYPE}-${TRACKNAME}-secret" | tr '[:upper:]' '[:lower:]')

# sys-ImagePath
IMAGE_PATH="\$(ACRPath-NonProd)/\$(${APPID}-${TRACKNAME}-ACRRepositoryName)"

# Write variable data
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
echo "🔹 AppCriticality: $APP_CRITICALITY"
echo "🔹 Namespace: $NAMESPACE"
echo "🔹 Secret Name: $SECRET_NAME"
echo "🔹 Image Path: $IMAGE_PATH"

HTTP_CODE=$(curl --http1.1 -s -w "%{http_code}" -o "$RESPONSE_FILE" -X POST \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "$BODY" "$URL")

if [[ "$HTTP_CODE" -ge 400 || "$HTTP_CODE" -eq 000 ]]; then
  echo "❌ ERROR: Failed to create variable group: $VG_NAME"
  cat "$RESPONSE_FILE"
else
  echo "✅ Successfully created variable group: $VG_NAME"
fi
