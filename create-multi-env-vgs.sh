#!/bin/bash

set -e

ENV="$1"
APPID="$2"
TRACKNAME="$3"
TRACKTYPE="$4"

if [[ -z "$ENV" || -z "$APPID" || -z "$TRACKNAME" || -z "$TRACKTYPE" ]]; then
  echo "❌ ERROR: Missing input arguments"
  exit 1
fi

ORG="${org:-${ORG}}"
PROJECT="${project:-${PROJECT}}"
PAT="${AZURE_DEVOPS_PAT}"

if [[ -z "$ORG" || -z "$PROJECT" || -z "$PAT" ]]; then
  echo "❌ ERROR: Missing org, project or PAT env variables"
  exit 1
fi

ENCODED_PAT=$(printf ":%s" "$PAT" | base64 | tr -d '\n')
AUTH_HEADER="Authorization: Basic $ENCODED_PAT"

# Project ID
PROJECT_API_URL="https://dev.azure.com/$ORG/_apis/projects/$PROJECT?api-version=7.1-preview.1"
PROJECT_ID=$(curl -s -H "$AUTH_HEADER" "$PROJECT_API_URL" | jq -r '.id')

VG_NAME="${ENV}-${APPID}-${TRACKNAME}-VG"

# sys-AppCriticality
case "$TRACKTYPE" in
  web)    CRIT="bcweb" ;;
  chatbot)
    if [[ "$ENV" =~ ^(PROD|DR)$ ]]; then
      CRIT="chatbotweb"
    else
      CRIT="devintweb-chatbot"
    fi
    ;;
  *)      CRIT="bcapi" ;;
esac

# sys-Namespace
case "$TRACKTYPE" in
  web)
    if [[ "$ENV" =~ ^(PROD|DR)$ ]]; then NS="bcweb"
    else NS="$(echo "$ENV" | awk '{print tolower($0)}')web-bc"; fi
    ;;
  chatbot)
    if [[ "$ENV" =~ ^(PROD|DR)$ ]]; then NS="chatbotweb"
    else NS="$(echo "$ENV" | awk '{print tolower($0)}')web-chatbot"; fi
    ;;
  *)
    if [[ "$ENV" =~ ^(PROD|DR)$ ]]; then NS="bcapi"
    else NS="$(echo "$ENV" | awk '{print tolower($0)}')api-bc"; fi
    ;;
esac

# sys-SecretResourceName
SECRET_NAME="$(echo "${ENV}-${APPID}-${TRACKTYPE}-${TRACKNAME}-secret" | tr '[:upper:]' '[:lower:]')"

# sys-ImagePath
IMAGE_PATH="\$(ACRPath-NonProd)/\$(appid(${APPID})-${TRACKNAME}-ACRRepositoryName)"

# Build payload
cat > variables.json <<EOF
{
  "MSI-Identitybinding": { "value": "default", "isSecret": false },
  "sys-AppCriticality": { "value": "${CRIT}", "isSecret": false },
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

URL="https://dev.azure.com/$ORG/$PROJECT/_apis/distributedtask/variablegroups?api-version=7.1-preview.2"
RESPONSE_FILE=$(mktemp)

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
