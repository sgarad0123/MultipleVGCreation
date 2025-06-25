#!/bin/bash

set -e

env="$1"
appid="$2"
trackname="$3"
tracktype="$4"

# Validate input
if [[ -z "$env" || -z "$appid" || -z "$trackname" || -z "$tracktype" ]]; then
  echo "❌ ERROR: Missing input arguments"
  echo "Usage: ./create-multi-env-vgs.sh <env> <appid> <trackname> <tracktype>"
  exit 1
fi

# Validate required variables
if [[ -z "$ORG" || -z "$PROJECT" || -z "$AZURE_DEVOPS_PAT" ]]; then
  echo "❌ ERROR: Missing org, project or PAT env variables"
  exit 1
fi

# Encode PAT
ENCODED_PAT=$(printf ":%s" "$AZURE_DEVOPS_PAT" | base64 | tr -d '\n')
AUTH_HEADER="Authorization: Basic $ENCODED_PAT"

# Get project ID
PROJECT_ID=$(curl -s -H "$AUTH_HEADER" \
  "https://dev.azure.com/$ORG/_apis/projects/$PROJECT?api-version=7.1-preview.1" | jq -r '.id')

if [[ "$PROJECT_ID" == "null" || -z "$PROJECT_ID" ]]; then
  echo "❌ ERROR: Failed to fetch project ID for $PROJECT"
  exit 1
fi

# Lowercase values
trackname_lc=$(echo "$trackname" | tr '[:upper:]' '[:lower:]')
tracktype_lc=$(echo "$tracktype" | tr '[:upper:]' '[:lower:]')
env_lc=$(echo "$env" | tr '[:upper:]' '[:lower:]')

# Determine sys-AppCriticality
if [[ "$tracktype_lc" == "web" ]]; then
  appCriticality="bcweb"
elif [[ "$tracktype_lc" == "chatbot" ]]; then
  appCriticality="chatbotweb"
else
  appCriticality="bcapi"
fi

# Determine sys-Namespace
if [[ "$env" == "PROD" || "$env" == "DR" ]]; then
  namespace="$appCriticality"
else
  if [[ "$tracktype_lc" == "web" ]]; then
    namespace="${env_lc}intweb-bc"
  elif [[ "$tracktype_lc" == "chatbot" ]]; then
    namespace="${env_lc}intweb-chatbot"
  else
    namespace="${env_lc}intapi-bc"
  fi
fi

# Construct variable group name
vg_name="${env}-${appid}-${trackname}-VG"

# Construct image path
imagePath="\$(ACRPath-NonProd)/\$(${appid}-${trackname}-ACRRepositoryName)"

# Construct secret resource name (lowercase)
secretName=$(echo "${env}-${appid}-${tracktype}-${trackname}-secret" | tr '[:upper:]' '[:lower:]')

# Always include MSI-Identitybinding
declare -A variables=(
  ["MSI-Identitybinding"]="default"
  ["sys-AppCriticality"]="$appCriticality"
  ["sys-Namespace"]="$namespace"
  ["sys-ImagePath"]="$imagePath"
  ["sys-SecretResourceName"]="$secretName"
)

# Create JSON
VARIABLES_JSON="{"
i=0
for key in "${!variables[@]}"; do
  VARIABLES_JSON+="\"$key\": { \"value\": \"${variables[$key]}\", \"isSecret\": false }"
  [[ $i -lt $((${#variables[@]} - 1)) ]] && VARIABLES_JSON+=","
  ((i++))
done
VARIABLES_JSON+="}"

echo "$VARIABLES_JSON" > variables.json

# Prepare payload
BODY=$(jq -n \
  --arg name "$vg_name" \
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

# Send request
URL="https://dev.azure.com/$ORG/$PROJECT/_apis/distributedtask/variablegroups?api-version=7.1-preview.2"
RESPONSE_FILE=$(mktemp)

HTTP_CODE=$(curl --http1.1 -s -w "%{http_code}" -o "$RESPONSE_FILE" -X POST \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "$BODY" "$URL")

echo "📡 Response Code: $HTTP_CODE"
cat "$RESPONSE_FILE"

if [[ "$HTTP_CODE" -ge 400 || "$HTTP_CODE" -eq 000 ]]; then
  echo "❌ ERROR: Failed to create variable group $vg_name"
else
  echo "✅ Variable group $vg_name created successfully!"
fi
