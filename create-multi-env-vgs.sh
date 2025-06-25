#!/bin/bash
set -e

# Arguments from the pipeline
ENV="$1"         # e.g., DEV, SIT
APPID="$2"       # e.g., myapp_id
TRACKNAME="$3"   # e.g., core
TRACKTYPE="$4"   # e.g., api, wa
APPTYPE="$5"     # e.g., api, func, chatbot
ORG="$6"         # Azure DevOps Organization name
PROJECT="$7"     # Azure DevOps Project name
PAT="$8"         # Azure DevOps Personal Access Token (PAT)

# --- Input Validation ---
if [[ -z "$ENV" || -z "$APPID" || -z "$TRACKNAME" || -z "$TRACKTYPE" || -z "$APPTYPE" || -z "$ORG" || -z "$PROJECT" || -z "$PAT" ]]; then
  echo "❌ ERROR: Missing one or more required input arguments."
  echo "Usage: ./create-multi-env-vgs.sh <ENV> <APPID> <TRACKNAME> <TRACKTYPE> <APPTYPE> <ORG> <PROJECT> <PAT>"
  exit 1
fi

echo "--- Script Execution Started ---"
echo "Arguments received: ENV=$ENV, APPID=$APPID, TRACKNAME=$TRACKNAME, TRACKTYPE=$TRACKTYPE, APPTYPE=$APPTYPE"
echo "Azure DevOps: Org=$ORG, Project=$PROJECT"

# --- Authentication Header ---
ENCODED_PAT=$(printf ":%s" "$PAT" | base64 | tr -d '\n')
AUTH_HEADER="Authorization: Basic $ENCODED_PAT"

# --- Get Project ID ---
echo "Fetching Project ID for project: $PROJECT in organization: $ORG"
PROJECT_ID=$(curl -s -H "$AUTH_HEADER" \
  "https://dev.azure.com/$ORG/_apis/projects/$PROJECT?api-version=7.1-preview.1" \
  | jq -r '.id')

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
  echo "❌ ERROR: Could not retrieve Project ID for '$PROJECT'. Check organization, project name, and PAT."
  exit 1
fi
echo "Project ID for '$PROJECT': $PROJECT_ID"

# --- Variable Group Name ---
VG_NAME="${ENV}-${APPID}-${TRACKNAME}-VG"
echo "Calculated Variable Group Name: $VG_NAME"

# --- AppCriticality Logic ---
CRIT=""
case "$APPTYPE" in
  chatbot) CRIT="chatbot" ;;
  wa) CRIT="bcweb" ;;
  contractautweb) CRIT="contractauthweb" ;;
  contractautapi) CRIT="contractauthapi" ;;
  api|func|bj) CRIT="bcapi" ;;
  *) CRIT="bcapi" ;; # Default case
esac
echo "AppCriticality (CRIT): $CRIT (based on APPTYPE: $APPTYPE)"

# --- Namespace Logic ---
ENV_LC=$(echo "$ENV" | tr '[:upper:]' '[:lower:]')
NS=""

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
echo "Namespace (NS): $NS (based on ENV: $ENV, APPTYPE: $APPTYPE, TRACKTYPE: $TRACKTYPE)"

# --- Secret Resource Name ---
SECRET_NAME=$(echo "${ENV}-${APPID}-${TRACKTYPE}-${TRACKNAME}-secret" | tr '[:upper:]' '[:lower:]')
echo "Secret Resource Name: $SECRET_NAME"

# --- Image Path ---
IMAGE_PATH="\$(ACRPath-NonProd)/\$(${APPID}-${TRACKNAME}-ACRRepositoryName)"
echo "Image Path: $IMAGE_PATH"

# --- Generate Variables JSON File ---
echo "Generating variables.json for variable group '$VG_NAME'..."
cat > variables.json <<EOF
{
  "MSI-Identitybinding": { "value": "default", "isSecret": false },
  "sys-AppCriticality": { "value": "${CRIT}", "isSecret": false },
  "sys-Namespace": { "value": "${NS}", "isSecret": false },
  "sys-SecretResourceName": { "value": "${SECRET_NAME}", "isSecret": false },
  "sys-ImagePath": { "value": "${IMAGE_PATH}", "isSecret": false }
}
EOF
echo "Content of variables.json:"
cat variables.json

# --- Construct Variable Group API Body ---
echo "Constructing API request body for variable group..."
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
echo "API Request Body generated."
# echo "$BODY" # Uncomment for full body debugging

# --- Call Azure DevOps API to Create Variable Group ---
RESPONSE_FILE=$(mktemp)
URL="https://dev.azure.com/$ORG/$PROJECT/_apis/distributedtask/variablegroups?api-version=7.1-preview.2"

echo "📦 Attempting to create variable group: $VG_NAME via URL: $URL"

HTTP_CODE=$(curl --http1.1 -s -w "%{http_code}" -o "$RESPONSE_FILE" -X POST \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "$BODY" "$URL")

# --- API Response Handling ---
if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "✅ Successfully created variable group: $VG_NAME (HTTP $HTTP_CODE)"
elif [[ "$HTTP_CODE" -eq 409 ]]; then
  echo "⚠️ Variable group '$VG_NAME' already exists (HTTP $HTTP_CODE)."
  echo "This is expected if running multiple times. No action needed."
  cat "$RESPONSE_FILE" # Still show response for context
else
  echo "❌ Failed to create variable group '$VG_NAME' (HTTP $HTTP_CODE)"
  echo "Error details:"
  cat "$RESPONSE_FILE"
  exit 1 # Exit with error code on failure
fi

echo "--- Script Execution Finished ---"
