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

if [[ -z "$ORG" || -z "$PROJECT" || -z "$PAT" ]]; then
  echo "❌ ERROR: Missing org, project or PAT env variables"
  exit 1
fi

ENCODED_PAT=$(printf ":%s" "$PAT" | base64 | tr -d '\n')
AUTH_HEADER="Authorization: Basic $ENCODED_PAT"

PROJECT_ID=$(curl -s -H "$AUTH_HEADER" \
  "https://dev.azure.com/$ORG/_apis/projects/$PROJECT?api-version=7.1-preview.1" \
  | jq -r '.id')

VG_NAME="${ENV}-${APPID}-${TRACKNAME}-VG"
ENV_LC="$(echo "$ENV" | awk '{print tolower($0)}')"

# sys-AppCriticality based on apptype
case "$APPTYPE" in
  chatbot)            CRIT="chatbot" ;;
  wa)                 CRIT="bcweb" ;;
  contractautweb)     CRIT="contractauthweb" ;;
  contractautapi)     CRIT="contractauthapi" ;;
  api|func|bj)        CRIT="bcapi" ;;
  *)                  CRIT="bcapi" ;;
esac

# sys-Namespace logic
if [[ "$APPTYPE" == "chatbot" && "$TRACKTYPE" == "wa" ]]; then
  case "$ENV" in
    DEV)   NS="devintweb-bc" ;;
    SIT)   NS="sitweb-bc" ;;
    UAT)   NS="uatweb-bc" ;;
    PT)    NS="ptweb-bc" ;;
    PROD|DR) NS="chatbotweb" ;;
    *)     NS="${ENV_LC}web-bc" ;;
  esac
elif [[ "$ENV" == "DEV" ]]; then
  NS="devintapi-bc"
elif [[ "$TRACKTYPE" == "wa" ]]; then
  case "$ENV" in
    SIT)   NS="sitweb-bc" ;;
    UAT)   NS="uatweb-bc" ;;
    PT)    NS="ptweb-bc" ;;
    PROD|DR) NS="bcweb" ;;
    *)     NS="${ENV_LC}web-bc" ;;
  esac
else
  case "$ENV" in
    PROD|DR) NS="bcapi" ;;
    *)       NS="${ENV_LC}api-bc" ;;
  esac
fi

SECRET_NAME="$(echo "${ENV}-${APPID}-${TRACKTYPE}-${TRACKNAME}-secret" | tr '[:upper:]' '[:lower:]')"
IMAGE_PATH="\$(ACRPath-NonProd)/\$(${APPID}-${TRACKNAME}-ACRRepositoryName)"

echo "----------------------------------------"
echo "🔧 Creating Variable Group: $VG_NAME"
echo "📌 ACR Image Path: $IMAGE_PATH"
echo "📌 Namespace: $NS"
echo "📌 AppCriticality: $CRIT"
echo "📌 Secret Resource Name: $SECRET_NAME"
echo "----------------------------------------"

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
