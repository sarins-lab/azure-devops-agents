#!/usr/bin/env bash
set -euo pipefail

restore_interactive_shell_path() {
  if command -v node >/dev/null 2>&1 && \
     { command -v mcp-server-azuredevops >/dev/null 2>&1 || command -v npx >/dev/null 2>&1; }; then
    return 0
  fi

  local nvm_bin=""
  nvm_bin="$(printf '%s\n' "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V | tail -n 1 || true)"
  if [[ -n "$nvm_bin" && -d "$nvm_bin" ]]; then
    case ":$PATH:" in
      *":$nvm_bin:"*) ;;
      *) PATH="$nvm_bin:$PATH" ;;
    esac
    export PATH

    if command -v node >/dev/null 2>&1 && \
       { command -v mcp-server-azuredevops >/dev/null 2>&1 || command -v npx >/dev/null 2>&1; }; then
      return 0
    fi
  fi

  local sentinel_start="__ADO_MCP_PATH_START__"
  local sentinel_end="__ADO_MCP_PATH_END__"
  local interactive_output=""
  local interactive_path=""
  local path_entry

  interactive_output="$(ADO_MCP_INTERACTIVE_PATH_BOOTSTRAP=1 bash -ic "printf '%s%s%s' '$sentinel_start' \"\$PATH\" '$sentinel_end'" 2>/dev/null || true)"
  if [[ "$interactive_output" != *"$sentinel_start"*"$sentinel_end"* ]]; then
    return 0
  fi

  interactive_path="${interactive_output#*${sentinel_start}}"
  interactive_path="${interactive_path%%${sentinel_end}*}"
  if [[ -z "$interactive_path" ]]; then
    return 0
  fi

  local old_ifs="$IFS"
  IFS=':'
  for path_entry in $interactive_path; do
    [[ -z "$path_entry" ]] && continue
    case ":$PATH:" in
      *":$path_entry:"*) ;;
      *) PATH="$path_entry:$PATH" ;;
    esac
  done
  IFS="$old_ifs"
  export PATH
}

restore_interactive_shell_path

require_node() {
  if ! command -v node >/dev/null 2>&1; then
    echo "Node.js 20 or later is required to load Azure DevOps MCP configuration. Install Node.js and retry." >&2
    exit 1
  fi

  local node_major
  node_major="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || true)"
  if ! [[ "$node_major" =~ ^[0-9]+$ ]] || (( node_major < 20 )); then
    echo "Node.js 20 or later is required; found $(node --version 2>/dev/null || echo unknown)." >&2
    exit 1
  fi
}

require_local_runner() {
  if command -v mcp-server-azuredevops >/dev/null 2>&1 || command -v npx >/dev/null 2>&1; then
    return 0
  fi

  echo "Azure DevOps MCP launcher requires either a global mcp-server-azuredevops binary or npx in PATH. Install npm with Node.js 20+ or install @azure-devops/mcp globally." >&2
  exit 1
}

require_node

load_config() {
  local file="$1"
  local prefix="$2"

  [[ -n "$file" && -f "$file" ]] || return 0

  eval "$(node - <<'NODE' "$file" "$prefix"
const fs = require("fs");
const [file, prefix] = process.argv.slice(2);
const raw = fs.readFileSync(file, "utf8").trim();
if (!raw) process.exit(0);

const data = JSON.parse(raw);
const shellQuote = (value) => "'" + String(value).replace(/'/g, "'\\''") + "'";
const emitString = (name, value) => {
  if (typeof value !== "string" || value.trim() === "") return;
  console.log(`${prefix}${name}=${shellQuote(value.trim())}`);
};

emitString("organization", data.organization);
emitString("authentication", data.authentication);
emitString("docker_image", data.dockerImage);
emitString("project", data.project);
emitString("team", data.team);

const domains = Array.isArray(data.domains)
  ? data.domains.filter((item) => item !== undefined && item !== null && String(item).trim() !== "")
  : [];
console.log(`${prefix}domains=(${domains.map((item) => shellQuote(String(item).trim())).join(" ")})`);
NODE
)"
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

user_config_organization=""
user_config_authentication=""
user_config_docker_image=""
user_config_project=""
user_config_team=""
user_config_domains=()
repo_config_project=""
repo_config_team=""
repo_config_domains=()

load_config "$user_config_path" "user_config_"
load_config "$repo_config_path" "repo_config_"

organization="${user_config_organization:-${ADO_MCP_ORG:-}}"
if [[ -z "$organization" ]]; then
  echo "Azure DevOps organization is not configured. Set ADO_MCP_ORG or create $user_config_path." >&2
  exit 1
fi

authentication="${user_config_authentication:-azcli}"
docker_image="${user_config_docker_image:-}"

if [[ -z "$docker_image" ]]; then
  require_local_runner
fi

project="${user_config_project:-${ADO_MCP_PROJECT:-}}"
team="${user_config_team:-${ADO_MCP_TEAM:-}}"
[[ -n "$repo_config_project" ]] && project="$repo_config_project"
[[ -n "$repo_config_team" ]] && team="$repo_config_team"

if [[ -n "$project" ]]; then
  export ado_mcp_project="$project"
fi
if [[ -n "$team" ]]; then
  export ado_mcp_team="$team"
fi

domains=("${user_config_domains[@]}")
if (( ${#repo_config_domains[@]} > 0 )); then
  domains=("${repo_config_domains[@]}")
fi

if [[ -n "$docker_image" ]]; then
  echo "WARNING: Docker MCP mode is experimental. Use the default global-binary mode where possible." >&2
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

bin_args=("$organization" "--authentication" "$authentication")
for domain in "${domains[@]}"; do
  bin_args+=("-d" "$domain")
done

# Prefer the globally installed binary for instant startup; fall back to npx.
if command -v mcp-server-azuredevops >/dev/null 2>&1; then
  exec mcp-server-azuredevops "${bin_args[@]}"
else
  exec npx -y @azure-devops/mcp "${bin_args[@]}"
fi
