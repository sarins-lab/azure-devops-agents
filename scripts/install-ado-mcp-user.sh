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

require_node() {
  if ! command -v node >/dev/null 2>&1; then
    echo "Node.js 20 or later is required. Install Node.js and retry." >&2
    exit 1
  fi

  local node_major
  node_major="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || true)"
  if ! [[ "$node_major" =~ ^[0-9]+$ ]] || (( node_major < 20 )); then
    echo "Node.js 20 or later is required; found $(node --version 2>/dev/null || echo unknown)." >&2
    exit 1
  fi

  if [[ "$mode" == "npx" ]] && \
     ! command -v mcp-server-azuredevops >/dev/null 2>&1 && \
     ! command -v npx >/dev/null 2>&1 && \
     ! command -v npm >/dev/null 2>&1; then
    echo "Non-Docker MCP mode requires mcp-server-azuredevops or npx at runtime. npm is accepted here because the installer will add the global binary via npm install. Install Node.js 20+ with npm, or install @azure-devops/mcp globally, or rerun with --mode docker." >&2
    exit 1
  fi
}

organization="${ADO_MCP_ORG:-}"
authentication="${ADO_MCP_AUTHENTICATION:-}"
domains_csv="${ADO_MCP_DOMAINS:-}"
_auth_from_cli=0
_domains_from_cli=0
existing_docker=""
existing_org=""
existing_project=""
existing_team=""
project="${ADO_MCP_PROJECT:-}"
team="${ADO_MCP_TEAM:-}"
mode="npx"
mode_explicit=0
docker_image=""
auth_token=""
clients_csv="All"
force=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/install.sh --organization <ado-org> [options]

Options:
  --organization <org>       Azure DevOps organization name. Required.
  --mode <npx|docker>        How to run the MCP server. Default: npx.
                               npx    — prefer globally installed binary, fall back to npx (recommended).
                               docker — [EXPERIMENTAL] run via Docker container;
                                        requires --docker-image and ADO_MCP_AUTH_TOKEN.
  --docker-image <image>     Docker image to use. Implies docker mode unless --mode was set explicitly.
  --auth-token <pat>         Persist PAT as ADO_MCP_AUTH_TOKEN (--mode docker only).
  --authentication <method>  MCP authentication method. Default: azcli.
  --domains <csv>            Comma-separated MCP domains.
  --project <project>        Default Azure DevOps project. Repo .ado-mcp.json overrides it.
  --team <team>              Default Azure DevOps team. Repo .ado-mcp.json overrides it.
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
    --mode)
      mode="${2:-}"
      mode_explicit=1
      shift 2
      ;;
    --authentication)
      authentication="${2:-}"
      _auth_from_cli=1
      shift 2
      ;;
    --domains)
      domains_csv="${2:-}"
      _domains_from_cli=1
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
# Must run before mode inference so a dockerImage in config correctly sets mode=docker.
_ado_existing_config="${ADO_MCP_HOME:-$HOME}/.ado-mcp/config.json"
if [[ -f "$_ado_existing_config" ]] && command -v node >/dev/null 2>&1; then
  if _ado_cfg="$(node -e '
const fs = require("fs");
const raw = fs.readFileSync(process.argv[1], "utf8").trim();
if (!raw) process.exit(0);
const d = JSON.parse(raw);
const get = k => { const v = d[k]; return v !== undefined && v !== null ? Array.isArray(v) ? v.join(",") : String(v) : ""; };
process.stdout.write(get("organization") + "\n" + get("project") + "\n" + get("team") + "\n" + get("dockerImage") + "\n" + get("authentication") + "\n" + get("domains") + "\n");
' "$_ado_existing_config" 2>/dev/null)"; then
    if [[ -n "$_ado_cfg" ]]; then
      { IFS= read -r _cfg_org; IFS= read -r _cfg_project; IFS= read -r _cfg_team; IFS= read -r _cfg_docker; IFS= read -r _cfg_auth; IFS= read -r _cfg_domains; } <<< "$_ado_cfg" || true
      [[ -z "$organization"  && -n "$_cfg_org" ]]     && organization="$_cfg_org"
      [[ -z "$project"       && -n "$_cfg_project" ]] && project="$_cfg_project"
      [[ -z "$team"          && -n "$_cfg_team" ]]    && team="$_cfg_team"
      [[ -z "$docker_image" && -n "$_cfg_docker" && ! ( "$mode" == "npx" && $mode_explicit -eq 1 ) ]] && docker_image="$_cfg_docker"
      [[ $_auth_from_cli    -eq 0 && -z "$authentication" && -n "$_cfg_auth" ]]   && authentication="$_cfg_auth"
      [[ $_domains_from_cli -eq 0 && -z "$domains_csv"   && -n "$_cfg_domains" ]] && domains_csv="$_cfg_domains"
      existing_org="$_cfg_org"
      existing_project="$_cfg_project"
      existing_team="$_cfg_team"
      existing_docker="$_cfg_docker"
      unset _cfg_org _cfg_project _cfg_team _cfg_docker _cfg_auth _cfg_domains
    fi
  else
    echo "Warning: could not parse existing config $_ado_existing_config — run with --organization to reconfigure." >&2
  fi
  unset _ado_cfg
fi
unset _ado_existing_config
[[ $_auth_from_cli    -eq 0 && -z "$authentication" ]] && authentication="azcli"
[[ $_domains_from_cli -eq 0 && -z "$domains_csv" ]]    && domains_csv="core,work,work-items,repositories,wiki"
unset _auth_from_cli _domains_from_cli

# Normalise mode — infer docker only when --mode was not provided explicitly.
if [[ -n "$docker_image" ]]; then
  if (( mode_explicit )); then
    if [[ "$mode" != "docker" ]]; then
      echo "--docker-image cannot be used with --mode $mode. Use --mode docker or omit --mode to infer Docker mode." >&2
      exit 1
    fi
  else
    mode="docker"
  fi
fi

if [[ -z "$organization" ]]; then
  echo "--organization is required." >&2
  usage >&2
  exit 1
fi

case "$mode" in
  npx)
    docker_image=""
    ;;
  docker)
    echo "WARNING: Docker mode is experimental and not recommended for general use." >&2
    echo "         Use --mode npx (the default) unless you have a specific reason." >&2
    if [[ -z "$docker_image" ]]; then
      echo "--docker-image is required when --mode docker is set." >&2
      exit 1
    fi
    if ! command -v docker >/dev/null 2>&1; then
      echo "Docker mode requires the Docker CLI in PATH. Install Docker or use --mode npx." >&2
      exit 1
    fi
    if [[ -z "$auth_token" && -z "${ADO_MCP_AUTH_TOKEN:-}" ]]; then
      echo "Docker mode requires ADO_MCP_AUTH_TOKEN in the environment or --auth-token <pat> to persist it." >&2
      exit 1
    fi
    ;;
  *)
    echo "Unknown --mode value: $mode. Expected 'npx' or 'docker'." >&2
    exit 1
    ;;
esac

require_node

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"
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

toml_string() {
  local value="${1//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

shell_quote() {
  local value="$1"
  printf "'%s'" "$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
}

join_sections() {
  local first=1
  for file in "$@"; do
    [[ -f "$file" ]] || { echo "Required install artifact not found: $file" >&2; exit 1; }
    if [[ $first -eq 0 ]]; then
      printf '\n\n'
    fi
    sed -e '${/^$/d;}' "$file"
    first=0
  done
}

# Removes a legacy disabledMcpjsonServers entry so the plugin-owned MCP declaration runs.
enable_plugin_mcp_json_server() {
  local settings_path="$1"
  local server_name="$2"
  [[ -f "$settings_path" ]] || return 0
  node - "$settings_path" "$server_name" <<'NODE'
const fs = require("fs");
const [settingsPath, serverName] = process.argv.slice(2);
try {
  const raw = fs.readFileSync(settingsPath, "utf8").trim();
  if (!raw) process.exit(0);
  const json = JSON.parse(raw);
  if (!Array.isArray(json.disabledMcpjsonServers) || !json.disabledMcpjsonServers.includes(serverName)) {
    process.exit(0);
  }
  const filtered = json.disabledMcpjsonServers.filter((entry) => entry !== serverName);
  if (filtered.length === 0) {
    delete json.disabledMcpjsonServers;
  } else {
    json.disabledMcpjsonServers = filtered;
  }
  fs.writeFileSync(settingsPath, JSON.stringify(json, null, 2) + "\n", "utf8");
  console.log(`  Enabled plugin .mcp.json server '${serverName}' in Claude settings: ${settingsPath}`);
} catch (err) {
  console.error(`  WARN: Could not parse ${settingsPath} — remove disabledMcpjsonServers manually. (${err.message})`);
}
NODE
}

merge_markdown_block() {
  local path="$1"
  local marker="$2"
  local content_file="$3"
  local force_flag="$4"
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
  mkdir -p "$(dirname "$mcp_path")" "$(dirname "$settings_path")"
  node - "$mcp_path" "$settings_path" "$launcher_path" "$context_path" "$force_flag" <<'NODE'
const fs = require("fs");
const [mcpPath, settingsPath, launcherPath, contextPath, forceFlag] = process.argv.slice(2);
const force = forceFlag === "1";
function readJson(path) {
  if (!fs.existsSync(path)) return {};
  const raw = fs.readFileSync(path, "utf8").trim();
  return raw ? JSON.parse(raw) : {};
}
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
function tryReadSettingsJson(path) {
  if (!fs.existsSync(path)) return {};
  const raw = fs.readFileSync(path, "utf8").trim();
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch (jsonError) {
    try {
      return JSON.parse(stripJsonc(raw));
    } catch (jsoncError) {
      console.error(`  WARN: Could not parse ${path} - skipping settings update. (${jsoncError.message})`);
      return null;
    }
  }
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
const settings = tryReadSettingsJson(settingsPath);
if (settings !== null) {
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
}
NODE
}

remove_legacy_vscode_prompts() {
  local settings_path="$1"
  local prompt_path="$2"
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
  if [[ "$mode" != "npx" ]]; then
    return 0
  fi

  if command -v mcp-server-azuredevops >/dev/null 2>&1; then
    echo "Global @azure-devops/mcp binary already available; skipping npm install."
    return 0
  fi

  if command -v npm >/dev/null 2>&1; then
    echo "Installing @azure-devops/mcp globally..."
    if npm install -g @azure-devops/mcp --silent; then
      local _npm_prefix _npm_bin
      _npm_prefix="$(npm prefix -g 2>/dev/null || true)"
      if [[ -n "$_npm_prefix" ]]; then
        _npm_bin="$_npm_prefix/bin"
        if [[ -d "$_npm_bin" ]]; then
          case ":$PATH:" in *":$_npm_bin:"*) ;; *) PATH="$_npm_bin:$PATH"; export PATH ;; esac
        fi
      fi
    else
      echo "WARN: global npm install failed - launcher will fall back to npx." >&2
    fi
  else
    echo "WARN: npm not found - skipping global install; launcher will use npx." >&2
  fi

  if ! command -v mcp-server-azuredevops >/dev/null 2>&1 && ! command -v npx >/dev/null 2>&1; then
    echo "No runnable MCP entrypoint: mcp-server-azuredevops and npx are both unavailable. Install npm with Node.js 20+ or install @azure-devops/mcp globally, then retry." >&2
    exit 1
  fi
}

remove_claude_user_mcp_server() {
  local success_message="$1"
  local not_found_message="$2"
  local failure_message="$3"
  local list_output line name output
  local removed=0
  local failed=0

  if ! list_output="$(claude mcp list 2>&1)"; then
    printf '%s\n' "$list_output" >&2
    echo "$failure_message" >&2
    return 0
  fi

  while IFS= read -r line; do
    [[ "$line" =~ \.ado-mcp[\\/](ado-mcp|ado-mcp-launcher)\.(sh|ps1) ]] || continue
    name="${line%%:*}"
    [[ -n "$name" ]] || continue

    if output="$(claude mcp remove --scope user "$name" 2>&1)"; then
      echo "  Removed legacy standalone MCP server: $name"
      removed=1
      continue
    fi

    if grep -Fq "No user-scoped MCP server found with name: $name" <<< "$output"; then
      continue
    fi

    printf '%s\n' "$output" >&2
    failed=1
  done <<< "$list_output"

  if (( failed != 0 )); then
    echo "$failure_message" >&2
    return 0
  fi

  if (( removed != 0 )); then
    echo "$success_message"
  else
    echo "$not_found_message"
  fi

  return 0
}

mkdir -p "$ado_home"
cp "$repo_root/scripts/ado-mcp-launcher.sh" "$launcher_target"
chmod 700 "$launcher_target"

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
elif [[ "$mode" == "npx" ]] && \
     ! command -v mcp-server-azuredevops >/dev/null 2>&1 && \
     ! command -v npx >/dev/null 2>&1; then
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

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
claude_context="$tmp_dir/claude-context.md"
codex_context="$tmp_dir/codex-context.md"
copilot_context="$tmp_dir/copilot-context.md"

join_sections \
  "$repo_root/plugins/azure-devops-agents-claude/CLAUDE.md" \
  "$repo_root/shared/workflows/rup-planning.md" \
  "$repo_root/shared/mcp/azure-devops-tools.md" > "$claude_context"

join_sections \
  "$repo_root/plugins/azure-devops-agents-codex/AGENTS.md" \
  "$repo_root/shared/workflows/rup-planning.md" \
  "$repo_root/shared/mcp/azure-devops-tools.md" > "$codex_context"

join_sections \
  "$repo_root/plugins/azure-devops-agents-vscode/copilot-instructions.md" \
  "$repo_root/shared/workflows/rup-planning.md" \
  "$repo_root/shared/mcp/azure-devops-tools.md" > "$copilot_context"

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

claude_plugin_installed=0
if [[ $configure_claude -eq 1 ]]; then
  echo "Configuring Claude Code..."
  if ! command -v claude >/dev/null 2>&1; then
    echo "  Claude CLI not found. Run manually after installing Claude Code:"
    echo "  claude plugin marketplace add --scope user \"$repo_root\""
    echo "  claude plugin install --scope user azure-devops-agents-claude@azure-devops-agents"
  else
    remove_claude_user_mcp_server \
      "  Removed legacy standalone MCP server registrations." \
      "  Legacy standalone MCP servers not registered, continuing." \
      "  WARN: could not remove legacy standalone MCP server registrations."
    if claude plugin marketplace list | grep -Eq '^[[:space:]]*>[[:space:]]+azure-devops-agents[[:space:]]*$'; then
      echo "  Claude marketplace already registered: azure-devops-agents"
    else
      claude plugin marketplace add --scope user "$repo_root"
    fi
    if claude plugin list | grep -Eq '^[[:space:]]*>[[:space:]]+azure-devops-agents-claude@azure-devops-agents[[:space:]]*$'; then
      echo "  Claude plugin already installed: azure-devops-agents-claude"
    else
      claude plugin install --scope user azure-devops-agents-claude@azure-devops-agents
    fi
    claude_plugin_installed=1
  fi
  merge_markdown_block "$user_home/.claude/CLAUDE.md" "azure-devops-agents" "$claude_context" "$force"
  enable_plugin_mcp_json_server "$user_home/.claude/settings.json" "azure-devops"
fi

echo
echo "Done. Client summary:"
if [[ $configure_claude -eq 1 ]]; then
  if [[ $claude_plugin_installed -eq 1 ]]; then
    echo "  Claude Code : plugin installed + plugin MCP enabled + ~/.claude/CLAUDE.md updated"
  else
    echo "  Claude Code : ~/.claude/CLAUDE.md updated (plugin install pending if Claude CLI was absent)"
  fi
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
