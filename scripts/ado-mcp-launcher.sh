#!/usr/bin/env bash
set -euo pipefail

json_value() {
  local file="$1"
  local key="$2"
  node -e '
const fs = require("fs");
const file = process.argv[1];
const key = process.argv[2];
if (!fs.existsSync(file)) process.exit(0);
const raw = fs.readFileSync(file, "utf8").trim();
if (!raw) process.exit(0);
const data = JSON.parse(raw);
const value = data[key];
if (value === undefined || value === null || value === "") process.exit(0);
if (Array.isArray(value)) {
  for (const item of value) {
    if (item !== undefined && item !== null && String(item).trim() !== "") {
      console.log(String(item));
    }
  }
} else {
  console.log(String(value));
}
' "$file" "$key"
}

find_repo_config() {
  if [[ -n "${ADO_MCP_REPO_CONFIG:-}" && -f "$ADO_MCP_REPO_CONFIG" ]]; then
    local config_dir
    config_dir="$(cd "$(dirname "$ADO_MCP_REPO_CONFIG")" >/dev/null 2>&1 && pwd -P)"
    printf '%s\n' "$config_dir/$(basename "$ADO_MCP_REPO_CONFIG")"
    return 0
  fi

  local current
  current="$(pwd -P)"
  while [[ -n "$current" && "$current" != "/" ]]; do
    if [[ -f "$current/.ado-mcp.json" ]]; then
      printf '%s\n' "$current/.ado-mcp.json"
      return 0
    fi
    current="$(dirname "$current")"
  done

  if [[ -f "/.ado-mcp.json" ]]; then
    printf '%s\n' "/.ado-mcp.json"
  fi
}

user_home="${ADO_MCP_HOME:-$HOME}"
ado_home="$user_home/.ado-mcp"
user_config_path="$ado_home/config.json"
env_path="$ado_home/env"

if [[ -f "$env_path" ]]; then
  set -a
  # shellcheck source=/dev/null
  . "$env_path"
  set +a
fi

repo_config_path="$(find_repo_config || true)"

organization="$(json_value "$user_config_path" "organization" | head -n 1 || true)"
organization="${organization:-${ADO_MCP_ORG:-}}"
if [[ -z "$organization" ]]; then
  echo "Azure DevOps organization is not configured. Set ADO_MCP_ORG or create $user_config_path." >&2
  exit 1
fi

authentication="$(json_value "$user_config_path" "authentication" | head -n 1 || true)"
authentication="${authentication:-azcli}"
docker_image="$(json_value "$user_config_path" "dockerImage" | head -n 1 || true)"

project=""
team=""
if [[ -n "$repo_config_path" ]]; then
  project="$(json_value "$repo_config_path" "project" | head -n 1 || true)"
  team="$(json_value "$repo_config_path" "team" | head -n 1 || true)"
fi

if [[ -n "$project" ]]; then
  export ado_mcp_project="$project"
fi
if [[ -n "$team" ]]; then
  export ado_mcp_team="$team"
fi

domains=()
while IFS= read -r domain; do
  [[ -n "$domain" ]] && domains+=("$domain")
done < <(json_value "$user_config_path" "domains" || true)

if [[ -n "$repo_config_path" ]]; then
  repo_domains=()
  while IFS= read -r domain; do
    [[ -n "$domain" ]] && repo_domains+=("$domain")
  done < <(json_value "$repo_config_path" "domains" || true)
  if (( ${#repo_domains[@]} > 0 )); then
    domains=("${repo_domains[@]}")
  fi
fi

if [[ -n "$docker_image" ]]; then
  if [[ -z "${ADO_MCP_AUTH_TOKEN:-}" ]]; then
    echo "Docker MCP mode requires ADO_MCP_AUTH_TOKEN in the host environment." >&2
    exit 1
  fi

  docker_args=("run" "-i" "--rm" "-e" "ADO_ORG=$organization" "-e" "ADO_MCP_AUTH_TOKEN")
  [[ -n "$project" ]] && docker_args+=("-e" "ado_mcp_project=$project")
  [[ -n "$team" ]] && docker_args+=("-e" "ado_mcp_team=$team")
  if (( ${#domains[@]} > 0 )); then
    domain_csv="$(IFS=,; printf '%s' "${domains[*]}")"
    docker_args+=("-e" "ADO_DOMAINS=$domain_csv")
  fi
  docker_args+=("$docker_image")

  exec docker "${docker_args[@]}"
fi

if [[ "$authentication" == "azcli" ]]; then
  if [[ -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" && -n "${AZURE_TENANT_ID:-}" ]]; then
    current_az_user="$(az account show --query user.name -o tsv --only-show-errors 2>/dev/null || true)"
    if [[ "$current_az_user" != "$AZURE_CLIENT_ID" ]]; then
      az login \
        --service-principal \
        --username "$AZURE_CLIENT_ID" \
        --password "$AZURE_CLIENT_SECRET" \
        --tenant "$AZURE_TENANT_ID" \
        --only-show-errors >/dev/null
    fi
  else
    if ! az account show --only-show-errors >/dev/null 2>&1; then
      echo "Azure CLI is not logged in, and service principal environment variables are not all set." >&2
      exit 1
    fi
  fi
fi

npx_args=("-y" "@azure-devops/mcp" "$organization" "--authentication" "$authentication")
for domain in "${domains[@]}"; do
  npx_args+=("-d" "$domain")
done

exec npx "${npx_args[@]}"
