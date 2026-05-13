#!/usr/bin/env bash
set -euo pipefail

restore_interactive_shell_path() {
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
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

    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
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
  local missing_path_entries=()
  IFS=':'
  for path_entry in $interactive_path; do
    [[ -z "$path_entry" ]] && continue
    case ":$PATH:" in
      *":$path_entry:"*) ;;
      *) missing_path_entries+=("$path_entry") ;;
    esac
  done
  IFS="$old_ifs"
  if (( ${#missing_path_entries[@]} > 0 )); then
    local missing_path
    missing_path="$(IFS=:; printf '%s' "${missing_path_entries[*]}")"
    if [[ -n "$PATH" ]]; then
      PATH="$missing_path:$PATH"
    else
      PATH="$missing_path"
    fi
  fi
  export PATH
}

restore_interactive_shell_path

organization="${ADO_MCP_ORG:-}"
authentication="${ADO_MCP_AUTHENTICATION:-azcli}"
domains_csv="${ADO_MCP_DOMAINS:-core,work,work-items,repositories,wiki}"
project="${ADO_MCP_PROJECT:-}"
team="${ADO_MCP_TEAM:-}"
docker_image="${ADO_MCP_DOCKER_IMAGE:-}"
auth_token="${ADO_MCP_AZ_AUTH_TOKEN:-}"
clients_csv="${ADO_MCP_CLIENTS:-All}"
force=0

case "${ADO_MCP_FORCE:-}" in
  1|true|TRUE|yes|YES) force=1 ;;
esac

usage() {
  cat <<'EOF'
Usage:
  install-online.sh --organization <ado-org> [options]

Options:
  --organization <org>       Azure DevOps organization name. Required unless ADO_MCP_ORG is set.
  --authentication <method>  MCP authentication method. Default: azcli.
  --domains <csv>            Comma-separated MCP domains.
  --project <project>        Default Azure DevOps project. Repo .ado-mcp.json overrides it.
  --team <team>              Default Azure DevOps team. Repo .ado-mcp.json overrides it.
  --docker-image <image>     Docker image for local stdio wrapper mode.
  --auth-token <pat>         Persist PAT for Docker mode in ~/.ado-mcp/env.
  --clients <csv>            All, Claude, VSCode, Codex. Default: All.
  --force                    Replace existing matching client config blocks.
  -h, --help                 Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --organization|-o)
      organization="${2:-}"
      shift 2
      ;;
    --authentication)
      authentication="${2:-}"
      shift 2
      ;;
    --domains)
      domains_csv="${2:-}"
      shift 2
      ;;
    --project)
      project="${2:-}"
      shift 2
      ;;
    --team)
      team="${2:-}"
      shift 2
      ;;
    --docker-image)
      docker_image="${2:-}"
      shift 2
      ;;
    --auth-token)
      auth_token="${2:-}"
      shift 2
      ;;
    --clients)
      clients_csv="${2:-}"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# Fall back to an existing ~/.ado-mcp/config.json so re-installs work without args.
_ado_existing_config="${ADO_MCP_HOME:-$HOME}/.ado-mcp/config.json"
if [[ -f "$_ado_existing_config" ]] && command -v node >/dev/null 2>&1; then
  _ado_cfg_get() {
    node -e '
const fs = require("fs");
const d = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const v = d[process.argv[2]];
if (v !== undefined && v !== null) {
  console.log(Array.isArray(v) ? v.join(",") : String(v));
}
' "$_ado_existing_config" "$1" 2>/dev/null || true
  }
  [[ -z "$organization" ]] && organization="$(_ado_cfg_get organization)"
  [[ -z "$project" ]]      && project="$(_ado_cfg_get project)"
  [[ -z "$team" ]]         && team="$(_ado_cfg_get team)"
  [[ -z "$docker_image" ]] && docker_image="$(_ado_cfg_get dockerImage)"
  unset -f _ado_cfg_get
fi
unset _ado_existing_config

if [[ -z "$organization" ]]; then
  echo "Azure DevOps organization is required. Pass --organization <org> or set ADO_MCP_ORG." >&2
  usage >&2
  exit 1
fi

user_home="${ADO_MCP_HOME:-$HOME}"
ado_home="$user_home/.ado-mcp"
launcher_target="$ado_home/ado-mcp-launcher.sh"
config_target="$ado_home/config.json"
env_target="$ado_home/env"
copilot_target="$ado_home/copilot-context.md"

configure_codex=0
configure_claude=0
configure_vscode=0
IFS=',' read -r -a clients <<< "$clients_csv"
for client in "${clients[@]}"; do
  normalized="$(printf '%s' "$client" | tr '[:upper:]' '[:lower:]' | xargs)"
  case "$normalized" in
    all)
      configure_codex=1
      configure_claude=1
      configure_vscode=1
      ;;
    codex)
      configure_codex=1
      ;;
    claude)
      configure_claude=1
      ;;
    vscode|vs-code|copilot)
      configure_vscode=1
      ;;
    "")
      ;;
    *)
      echo "Unknown client: $client" >&2
      exit 1
      ;;
  esac
done

require_node() {
  if ! command -v node >/dev/null 2>&1; then
    echo "Node.js 20 or later is required." >&2
    exit 1
  fi

  local node_major
  node_major="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || true)"
  if ! [[ "$node_major" =~ ^[0-9]+$ ]] || (( node_major < 20 )); then
    echo "Node.js 20 or later is required; found $(node --version 2>/dev/null || echo unknown)." >&2
    exit 1
  fi

  if [[ -z "$docker_image" ]] && \
     ! command -v mcp-server-azuredevops >/dev/null 2>&1 && \
     ! command -v npx >/dev/null 2>&1; then
    echo "Non-Docker MCP mode requires either a global mcp-server-azuredevops binary or npx. Install npm with Node.js 20+ or install @azure-devops/mcp globally." >&2
    exit 1
  fi
}

json_get() {
  local file="$1"
  local key="$2"
  require_node
  node -e '
const fs = require("fs");
const file = process.argv[1];
const key = process.argv[2];
if (!fs.existsSync(file)) process.exit(0);
const raw = fs.readFileSync(file, "utf8").trim();
if (!raw) process.exit(0);
const value = JSON.parse(raw)[key];
if (value === undefined || value === null) process.exit(0);
if (Array.isArray(value)) console.log(value.join(","));
else console.log(String(value));
' "$file" "$key"
}

toml_string() {
  local value="${1//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

shell_quote() {
  local value="$1"
  printf "'%s'" "$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
}

write_file() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path"
}

merge_markdown_block() {
  local path="$1"
  local marker="$2"
  local content_file="$3"
  local force_flag="$4"
  require_node
  mkdir -p "$(dirname "$path")"
  node - "$path" "$marker" "$content_file" "$force_flag" <<'NODE'
const fs = require("fs");
const [path, marker, contentFile, forceFlag] = process.argv.slice(2);
const force = forceFlag === "1";
const start = `<!-- ${marker}: start -->`;
const end = `<!-- ${marker}: end -->`;
const content = fs.readFileSync(contentFile, "utf8").trim();
const block = `${start}\n${content}\n${end}`;
let existing = fs.existsSync(path) ? fs.readFileSync(path, "utf8") : "";
if (existing.includes(start)) {
  if (!force) {
    console.log(`  Already installed. Use --force to update: ${path}`);
    process.exit(0);
  }
  const escapedStart = start.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const escapedEnd = end.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  existing = existing.replace(new RegExp(`${escapedStart}[\\s\\S]*?${escapedEnd}`), block);
} else {
  const sep = existing && !existing.endsWith("\n") ? "\n\n" : "\n";
  existing = `${existing}${sep}${block}\n`;
}
fs.writeFileSync(path, existing, "utf8");
console.log(`  Context block written: ${path}`);
NODE
}

merge_vscode_json() {
  local mcp_path="$1"
  local settings_path="$2"
  local launcher_path="$3"
  local context_path="$4"
  local force_flag="$5"
  require_node
  mkdir -p "$(dirname "$mcp_path")" "$(dirname "$settings_path")"
  node - "$mcp_path" "$settings_path" "$launcher_path" "$context_path" "$force_flag" <<'NODE'
const fs = require("fs");
const [mcpPath, settingsPath, launcherPath, contextPath, forceFlag] = process.argv.slice(2);
const force = forceFlag === "1";
function readJson(path) {
  if (!fs.existsSync(path)) return {};
  const raw = fs.readFileSync(path, "utf8").trim();
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch (jsonError) {
    try {
      return JSON.parse(stripJsonCommentsAndTrailingCommas(raw));
    } catch (jsoncError) {
      throw new Error(`Unable to parse JSON/JSONC file ${path}: ${jsoncError.message}`);
    }
  }
}
function stripJsonCommentsAndTrailingCommas(input) {
  let withoutComments = "";
  let inString = false;
  let escaped = false;
  let inLineComment = false;
  let inBlockComment = false;
  for (let index = 0; index < input.length; index += 1) {
    const char = input[index];
    const next = input[index + 1];
    if (inLineComment) {
      if (char === "\n" || char === "\r") {
        inLineComment = false;
        withoutComments += char;
      }
      continue;
    }
    if (inBlockComment) {
      if (char === "*" && next === "/") {
        inBlockComment = false;
        index += 1;
      }
      continue;
    }
    if (inString) {
      withoutComments += char;
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === "\"") inString = false;
      continue;
    }
    if (char === "\"") {
      inString = true;
      withoutComments += char;
      continue;
    }
    if (char === "/" && next === "/") {
      inLineComment = true;
      index += 1;
      continue;
    }
    if (char === "/" && next === "*") {
      inBlockComment = true;
      index += 1;
      continue;
    }
    withoutComments += char;
  }

  let output = "";
  inString = false;
  escaped = false;
  for (let index = 0; index < withoutComments.length; index += 1) {
    const char = withoutComments[index];
    if (inString) {
      output += char;
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === "\"") inString = false;
      continue;
    }
    if (char === "\"") {
      inString = true;
      output += char;
      continue;
    }
    if (char === ",") {
      let lookahead = index + 1;
      while (lookahead < withoutComments.length && /\s/.test(withoutComments[lookahead])) {
        lookahead += 1;
      }
      if (withoutComments[lookahead] === "}" || withoutComments[lookahead] === "]") {
        continue;
      }
    }
    output += char;
  }
  return output;
}
function writeJson(path, value) {
  fs.mkdirSync(require("path").dirname(path), { recursive: true });
  fs.writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}
function backupBeforeJsonRewrite(path) {
  if (!fs.existsSync(path)) return;
  const backupPath = `${path}.ado-mcp.${Date.now()}.bak`;
  fs.copyFileSync(path, backupPath);
  console.log(`  Backed up file before JSON rewrite: ${backupPath}`);
}
const mcp = readJson(mcpPath);
mcp.servers = mcp.servers || {};
if (!mcp.servers["azure-devops"] || force) {
  mcp.servers["azure-devops"] = {
    type: "stdio",
    command: "bash",
    args: [launcherPath]
  };
  writeJson(mcpPath, mcp);
  console.log(`  Configured VS Code MCP: ${mcpPath}`);
} else {
  console.log(`  MCP entry already present. Use --force to replace: ${mcpPath}`);
}
const settings = readJson(settingsPath);
let settingsChanged = false;
const instructionKey = "github.copilot.chat.codeGeneration.instructions";
const instructions = Array.isArray(settings[instructionKey]) ? settings[instructionKey] : [];
const instructionPresent = instructions.some((item) => item && item.file === contextPath);
if (instructionPresent && !force) {
  console.log(`  Copilot instruction already present. Use --force to update: ${settingsPath}`);
} else {
  settings[instructionKey] = instructions.filter((item) => !(item && item.file === contextPath));
  settings[instructionKey].push({ file: contextPath });
  settingsChanged = true;
}
if (settingsChanged) {
  backupBeforeJsonRewrite(settingsPath);
  writeJson(settingsPath, settings);
  console.log(`  Updated VS Code settings: ${settingsPath}`);
}
NODE
}

remove_legacy_vscode_prompts() {
  local settings_path="$1"
  local prompt_path="$2"
  require_node
  node - "$settings_path" "$prompt_path" <<'NODE'
const fs = require("fs");
const [settingsPath, promptPath] = process.argv.slice(2);
if (!fs.existsSync(settingsPath)) process.exit(0);
const raw = fs.readFileSync(settingsPath, "utf8").trim();
if (!raw) process.exit(0);
function stripJsonc(text) {
  let out = "", inStr = false, escaped = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i], next = text[i + 1];
    if (escaped) { out += ch; escaped = false; continue; }
    if (inStr && ch === "\\") { out += ch; escaped = true; continue; }
    if (ch === '"') { inStr = !inStr; out += ch; continue; }
    if (inStr) { out += ch; continue; }
    if (ch === "/" && next === "/") { while (i < text.length && text[i] !== "\n") i++; continue; }
    if (ch === "/" && next === "*") { i += 2; while (i < text.length && !(text[i] === "*" && text[i + 1] === "/")) i++; i++; continue; }
    out += ch;
  }
  return out.replace(/,(\s*[}\]])/g, "$1");
}
let settings;
try {
  settings = JSON.parse(stripJsonc(raw));
} catch (err) {
  console.error(`  WARN: Could not parse ${settingsPath} - skipping prompt cleanup. (${err.message})`);
  process.exit(0);
}
const key = "chat.promptFilesLocations";
let changed = false;
if (settings[key] && typeof settings[key] === "object" && !Array.isArray(settings[key]) && Object.prototype.hasOwnProperty.call(settings[key], promptPath)) {
  delete settings[key][promptPath];
  changed = true;
  console.log(`  Removed legacy VS Code prompt location: ${promptPath}`);
}
if (settings[key] && typeof settings[key] === "object" && !Array.isArray(settings[key]) && Object.keys(settings[key]).length === 0) {
  delete settings[key];
  changed = true;
  console.log("  Removed empty VS Code prompt location setting");
}
if (changed) {
  const backupPath = `${settingsPath}.ado-mcp.${Date.now()}.bak`;
  fs.copyFileSync(settingsPath, backupPath);
  console.log(`  Backed up file before JSON rewrite: ${backupPath}`);
  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n", "utf8");
}
NODE
  if [[ -d "$prompt_path" ]]; then
    rm -rf "$prompt_path"
    echo "  Removed legacy VS Code prompts: $prompt_path"
  fi
}

write_codex_toml() {
  local codex_toml="$1"
  local launcher_path="$2"
  local force_flag="$3"
  require_node
  mkdir -p "$(dirname "$codex_toml")"
  local block
  block="$(printf '\n[mcp_servers.azure-devops]\ncommand = "bash"\nargs = [%s]\n' "$(toml_string "$launcher_path")")"
  node - "$codex_toml" "$block" "$force_flag" <<'NODE'
const fs = require("fs");
const [path, block, forceFlag] = process.argv.slice(2);
const force = forceFlag === "1";
let existing = fs.existsSync(path) ? fs.readFileSync(path, "utf8") : "";
if (/^\[mcp_servers\.azure-devops\]/m.test(existing)) {
  if (!force) {
    console.log(`  Codex MCP already configured. Use --force to replace: ${path}`);
    process.exit(0);
  }
  existing = existing.replace(/^\[mcp_servers\.azure-devops\]\r?\n[\s\S]*?(?=^\[|\s*$)/m, block.trim() + "\n");
} else {
  existing += block;
}
fs.writeFileSync(path, existing, "utf8");
console.log(`  Configured Codex MCP: ${path}`);
NODE
}

vscode_user_dir() {
  case "$(uname -s)" in
    Darwin)
      printf '%s\n' "$HOME/Library/Application Support/Code/User"
      ;;
    Linux)
      printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
      ;;
    *)
      echo "Unsupported OS for VS Code path detection: $(uname -s)" >&2
      exit 1
      ;;
  esac
}

install_global_mcp_if_missing() {
  if [[ -n "$docker_image" ]]; then
    return 0
  fi

  if command -v mcp-server-azuredevops >/dev/null 2>&1; then
    echo "Global @azure-devops/mcp binary already available; skipping npm install."
    return 0
  fi

  if command -v npm >/dev/null 2>&1; then
    echo "Installing @azure-devops/mcp globally..."
    npm install -g @azure-devops/mcp --silent || echo "WARN: global npm install failed - launcher will fall back to npx." >&2
  else
    echo "WARN: npm not found - skipping global install; launcher will use npx." >&2
  fi
}

make_temp_dir() {
  local attempt base dir

  if command -v mktemp >/dev/null 2>&1; then
    if dir="$(mktemp -d 2>/dev/null)"; then
      printf '%s\n' "$dir"
      return
    fi

    if dir="$(mktemp -d -t ado-mcp 2>/dev/null)"; then
      printf '%s\n' "$dir"
      return
    fi
  fi

  base="${TMPDIR:-/tmp}"
  for attempt in 1 2 3 4 5; do
    dir="$base/ado-mcp.$$.$RANDOM.$attempt"
    if mkdir -m 700 "$dir" 2>/dev/null; then
      printf '%s\n' "$dir"
      return
    fi
  done

  echo "Unable to create temporary directory." >&2
  exit 1
}

tmp_dir="$(make_temp_dir)"
trap 'rm -rf "$tmp_dir"' EXIT
codex_context="$tmp_dir/codex-context.md"
claude_context="$tmp_dir/claude-context.md"
copilot_context="$tmp_dir/copilot-context.md"

mkdir -p "$ado_home"
write_file "$launcher_target" <<'LAUNCHER'
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

project="$(json_value "$user_config_path" "project" | head -n 1 || true)"
project="${project:-${ADO_MCP_PROJECT:-}}"
team="$(json_value "$user_config_path" "team" | head -n 1 || true)"
team="${team:-${ADO_MCP_TEAM:-}}"
if [[ -n "$repo_config_path" ]]; then
  repo_project="$(json_value "$repo_config_path" "project" | head -n 1 || true)"
  repo_team="$(json_value "$repo_config_path" "team" | head -n 1 || true)"
  [[ -n "$repo_project" ]] && project="$repo_project"
  [[ -n "$repo_team" ]] && team="$repo_team"
fi

[[ -n "$project" ]] && export ado_mcp_project="$project"
[[ -n "$team" ]] && export ado_mcp_team="$team"

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
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker MCP mode requires the Docker CLI in PATH. Install Docker or configure non-Docker MCP mode." >&2
    exit 1
  fi
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

if ! command -v mcp-server-azuredevops >/dev/null 2>&1 && ! command -v npx >/dev/null 2>&1; then
  echo "Azure DevOps MCP launcher requires either a global mcp-server-azuredevops binary or npx in PATH. Install npm with Node.js 20+ or install @azure-devops/mcp globally." >&2
  exit 1
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
LAUNCHER
chmod 700 "$launcher_target"
echo "Wrote online MCP launcher: $launcher_target"

existing_docker=""
existing_org=""
existing_project=""
existing_team=""
if [[ -f "$config_target" ]]; then
  existing_docker="$(json_get "$config_target" "dockerImage" || true)"
  existing_org="$(json_get "$config_target" "organization" || true)"
  existing_project="$(json_get "$config_target" "project" || true)"
  existing_team="$(json_get "$config_target" "team" || true)"
fi

if [[ -z "$project" ]]; then
  project="$existing_project"
fi
if [[ -z "$team" ]]; then
  team="$existing_team"
fi
if [[ -z "$project" && -t 0 ]]; then
  read -r -p "Default Azure DevOps project (optional; repo .ado-mcp.json overrides): " project
fi
if [[ -n "$project" && -z "$team" && -t 0 ]]; then
  read -r -p "Default Azure DevOps team (optional; repo .ado-mcp.json overrides): " team
fi

incoming_docker="$docker_image"
config_changed=1
if [[ -f "$config_target" && $force -eq 0 ]]; then
  if [[ "$existing_docker" != "$incoming_docker" || "$existing_org" != "$organization" || "$existing_project" != "$project" || "$existing_team" != "$team" ]]; then
    echo "Config already exists with different settings. Use --force to overwrite: $config_target" >&2
    exit 1
  fi
  echo "MCP config already exists and matches - skipping (use --force to replace): $config_target"
  config_changed=0
else
  config_authentication="$authentication"
  if [[ -n "$docker_image" ]]; then
    config_authentication="envvar"
  fi

  require_node
  node - "$config_target" "$organization" "$config_authentication" "$domains_csv" "$docker_image" "$project" "$team" <<'NODE'
const fs = require("fs");
const [path, organization, authentication, domainsCsv, dockerImage, project, team] = process.argv.slice(2);
const config = {
  organization,
  authentication,
  domains: domainsCsv.split(",").map((item) => item.trim()).filter(Boolean)
};
if (project) config.project = project;
if (team) config.team = team;
if (dockerImage) config.dockerImage = dockerImage;
fs.mkdirSync(require("path").dirname(path), { recursive: true });
fs.writeFileSync(path, `${JSON.stringify(config, null, 2)}\n`, "utf8");
NODE
  echo "Wrote MCP config: $config_target"
fi

if (( config_changed != 0 || force != 0 )); then
  install_global_mcp_if_missing
elif [[ "$mode" == "npx" ]]; then
  echo "Global @azure-devops/mcp install check skipped because MCP config already matches. Use --force to retry."
fi

if [[ -n "$docker_image" && -n "$auth_token" ]]; then
  printf 'export ADO_MCP_AUTH_TOKEN=%s\n' "$(shell_quote "$auth_token")" > "$env_target"
  chmod 600 "$env_target"
  export ADO_MCP_AUTH_TOKEN="$auth_token"
  echo "Stored ADO_MCP_AUTH_TOKEN in $env_target for Docker MCP mode."
fi

cat > "$codex_context" <<'EOF'
# Azure DevOps RUP Planning

The `azure-devops` MCP server is configured at user level via `~/.codex/config.toml`.
The installer stores a default `project` and optional `team` in `~/.ado-mcp/config.json`. Place `.ado-mcp.json` in any repo root to override `project` and `team`; the launcher injects the resolved values automatically.

Plan using RUP-style concepts: Stakeholder Request, Functional Requirement, Non-Functional Requirement, UX Artifact, Technical Requirement, Architecture, Technical Documentation, Delivery Slice, and Task.

Preferred routes: `/capture-request`, `/define-requirements`, `/design-ux`, `/plan-requirement`, `/document-solution`, `/plan-delivery`, `/plan-task`.

Natural planning phrases such as "I want to", "we need to", "setup", "build", "design", "implement", "secure", "expose", "document", "diagram", and "break down" should trigger planning even when Azure DevOps or RUP is not mentioned.

Before implementation, repository edits, deployment, or configuration work starts, verify traceability to an existing approved Azure DevOps work item or confirmed RUP planning artifact. If the requested work is not already represented in Azure DevOps, capture it as a new Stakeholder Request or Change Request and run the SDLC workflow first. User-facing work must include UX or an explicit UX-not-applicable decision.

Architecture must be cohesive, not a technology list. Technical documentation must not introduce architecture decisions. Mermaid diagrams for Azure DevOps wiki must use ::: mermaid blocks, graph TD; or graph LR; for flowcharts, simple node IDs, quoted ASCII labels, no HTML, no Markdown labels, no angle-bracket placeholders, no raw Unicode symbols, and no GitHub-style Mermaid code fences.

Do not create Azure DevOps work items until the user confirms the plan.

# Azure DevOps MCP Tooling

Use Microsoft's official `@azure-devops/mcp` package through the `azure-devops` MCP server.

Tool names use the `mcp_ado_*` naming pattern.

Use RUP-style SDLC concepts as the planning model. Include UX artifacts, architecture, and technical documentation as traceable planning artifacts. Before writing, call `mcp_ado_wit_list_backlogs` and `mcp_ado_wit_get_work_item_type` to derive the active Azure DevOps process profile.

Architecture must be cohesive: boundaries, components, runtime flows, deployment, data, security, operations, decisions, tradeoffs, and open questions. Mermaid diagrams for Azure DevOps wiki must use ::: mermaid blocks, graph TD; or graph LR; for flowcharts, simple node IDs, quoted ASCII labels, no HTML, no Markdown labels, no angle-bracket placeholders, no raw Unicode symbols, and no GitHub-style Mermaid code fences.

`mcp_ado_wit_add_child_work_items` creates child work items and parent links. It supports title, description, area path, iteration path, and Markdown/HTML format.

It does not set Acceptance Criteria, Story Points, Effort, Size, Requirement Type, Tags, or custom fields. Add those afterward with `mcp_ado_wit_update_work_item` only when the target work item type exposes those fields.

Use `mcp_ado_wit_work_items_link` only to repair or add links after creation.

For backlog lookup, call `mcp_ado_wit_list_backlogs` first, then call `mcp_ado_wit_list_backlog_work_items` with `project`, `team`, and `backlogId`.

For wiki lookup, use `mcp_ado_wiki_list_wikis`, `mcp_ado_wiki_list_pages`, `mcp_ado_wiki_get_page`, and `mcp_ado_wiki_get_page_content`.
EOF

cat > "$claude_context" <<'EOF'
# Azure DevOps RUP Planning

Use the `azure-devops` MCP server for Azure DevOps planning work. The installer stores a default `project` and optional `team` in `~/.ado-mcp/config.json`. Place `.ado-mcp.json` in any repo root to override `project` and `team`; the launcher injects the resolved values automatically.

Plan using RUP-style concepts: Stakeholder Request, Functional Requirement, Non-Functional Requirement, UX Artifact, Technical Requirement, Architecture, Technical Documentation, Delivery Slice, and Task.

Natural planning phrases such as "I want to", "we need to", "setup", "build", "design", "implement", "secure", "expose", "document", "diagram", and "break down" should trigger planning even when Azure DevOps or RUP is not mentioned.

Before implementation, repository edits, deployment, or configuration work starts, verify traceability to an existing approved Azure DevOps work item or confirmed RUP planning artifact. If the requested work is not already represented in Azure DevOps, capture it as a new Stakeholder Request or Change Request and run the SDLC workflow first. User-facing work must include UX or an explicit UX-not-applicable decision.

Architecture must be cohesive, not a technology list. Technical documentation must not introduce architecture decisions. Mermaid diagrams for Azure DevOps wiki must use ::: mermaid blocks, graph TD; or graph LR; for flowcharts, simple node IDs, quoted ASCII labels, no HTML, no Markdown labels, no angle-bracket placeholders, no raw Unicode symbols, and no GitHub-style Mermaid code fences.

Pause after each SDLC role phase. Never create Azure DevOps work items until the user confirms the plan.

Use Microsoft's official `@azure-devops/mcp` package. Tool names use the `mcp_ado_*` naming pattern.
EOF

cat > "$copilot_context" <<'EOF'
# Azure DevOps RUP Planning

Use the `azure-devops` MCP server for all Azure DevOps operations. The installer stores a default project and optional team in `~/.ado-mcp/config.json`; the launcher reads `.ado-mcp.json` from the repo root to override those values when present.

Plan using RUP-style concepts: Stakeholder Request, Functional Requirement, Non-Functional Requirement, UX Artifact, Technical Requirement, Architecture, Technical Documentation, Delivery Slice, and Task.

Recognize `/capture-request`, `/define-requirements`, `/design-ux`, `/plan-requirement`, `/document-solution`, `/plan-delivery`, `/plan-task`, and natural planning intent.

Natural planning phrases such as "I want to", "we need to", "setup", "build", "design", "implement", "secure", "expose", "document", "diagram", and "break down" should trigger planning even when Azure DevOps or RUP is not mentioned.

Before implementation, repository edits, deployment, or configuration work starts, verify traceability to an existing approved Azure DevOps work item or confirmed RUP planning artifact. If the requested work is not already represented in Azure DevOps, capture it as a new Stakeholder Request or Change Request and run the SDLC workflow first. User-facing work must include UX or an explicit UX-not-applicable decision.

Architecture must be cohesive, not a technology list. Technical documentation must not introduce architecture decisions. Mermaid diagrams for Azure DevOps wiki must use ::: mermaid blocks, graph TD; or graph LR; for flowcharts, simple node IDs, quoted ASCII labels, no HTML, no Markdown labels, no angle-bracket placeholders, no raw Unicode symbols, and no GitHub-style Mermaid code fences.

Use Microsoft's official `@azure-devops/mcp` package. Tool names use the `mcp_ado_*` naming pattern.
EOF

if [[ $configure_codex -eq 1 ]]; then
  echo "Configuring Codex..."
  codex_dir="$user_home/.codex"
  write_codex_toml "$codex_dir/config.toml" "$launcher_target" "$force"
  merge_markdown_block "$codex_dir/AGENTS.md" "azure-devops-agents" "$codex_context" "$force"
fi

if [[ $configure_vscode -eq 1 ]]; then
  echo "Configuring VS Code..."
  cp "$copilot_context" "$copilot_target"

  vs_code_dir="$(vscode_user_dir)"
  merge_vscode_json "$vs_code_dir/mcp.json" "$vs_code_dir/settings.json" "$launcher_target" "$copilot_target" "$force"
  remove_legacy_vscode_prompts "$vs_code_dir/settings.json" "$ado_home/prompts"
fi

if [[ $configure_claude -eq 1 ]]; then
  echo "Configuring Claude Code..."
  echo "  The online installer writes ~/.claude/CLAUDE.md only."
  echo "  Installing the Claude plugin-owned MCP server requires a local repo checkout."
  echo "  Use scripts/install.ps1 or scripts/install.sh from a clone to install azure-devops-agents-claude."
  merge_markdown_block "$user_home/.claude/CLAUDE.md" "azure-devops-agents" "$claude_context" "$force"
fi

echo
echo "Done. Client summary:"
if [[ $configure_claude -eq 1 ]]; then
  echo "  Claude Code : ~/.claude/CLAUDE.md updated (plugin install requires a local repo checkout)"
fi
[[ $configure_codex -eq 1 ]] && echo "  Codex       : MCP registered + ~/.codex/AGENTS.md updated"
[[ $configure_vscode -eq 1 ]] && echo "  VS Code     : MCP registered + Copilot instruction added"
echo
if [[ -n "$docker_image" ]]; then
  echo "Docker auth      : set ADO_MCP_AUTH_TOKEN before starting any tool, or use --auth-token."
else
  echo "Auth defaults to azcli. Run 'az login' if needed."
fi
echo 'Per-repo config  : add .ado-mcp.json -> { "project": "YourProject", "team": "YourTeam" }'
echo "Project default  : stored in ~/.ado-mcp/config.json; repo .ado-mcp.json overrides it when present."
