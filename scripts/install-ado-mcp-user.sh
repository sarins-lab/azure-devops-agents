#!/usr/bin/env bash
set -euo pipefail

organization=""
authentication="azcli"
domains_csv="core,work,work-items,repositories,wiki"
mode="npx"
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
                               npx    — use globally installed binary (recommended).
                               docker — [EXPERIMENTAL] run via Docker container;
                                        requires --docker-image and ADO_MCP_AUTH_TOKEN.
  --docker-image <image>     Docker image to use (--mode docker only).
  --auth-token <pat>         Persist PAT as ADO_MCP_AUTH_TOKEN (--mode docker only).
  --authentication <method>  MCP authentication method. Default: azcli.
  --domains <csv>            Comma-separated MCP domains.
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

# Normalise mode — infer docker if --docker-image was provided without --mode
if [[ -n "$docker_image" && "$mode" == "npx" ]]; then
  mode="docker"
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
    ;;
  *)
    echo "Unknown --mode value: $mode. Expected 'npx' or 'docker'." >&2
    exit 1
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"
user_home="${ADO_MCP_HOME:-$HOME}"
ado_home="$user_home/.ado-mcp"
launcher_target="$ado_home/ado-mcp-launcher.sh"
config_target="$ado_home/config.json"
env_target="$ado_home/env"
copilot_target="$ado_home/copilot-context.md"
prompt_dir="$ado_home/prompts"
prompt_source_dir="$repo_root/plugins/azure-devops-agents-vscode/prompts"

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

json_get() {
  local file="$1"
  local key="$2"
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
  local prompts_path="$5"
  local force_flag="$6"
  mkdir -p "$(dirname "$mcp_path")" "$(dirname "$settings_path")"
  node - "$mcp_path" "$settings_path" "$launcher_path" "$context_path" "$prompts_path" "$force_flag" <<'NODE'
const fs = require("fs");
const [mcpPath, settingsPath, launcherPath, contextPath, promptsPath, forceFlag] = process.argv.slice(2);
const force = forceFlag === "1";
function readJson(path) {
  if (!fs.existsSync(path)) return {};
  const raw = fs.readFileSync(path, "utf8").trim();
  return raw ? JSON.parse(raw) : {};
}
function writeJson(path, value) {
  fs.mkdirSync(require("path").dirname(path), { recursive: true });
  fs.writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
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
const instructionKey = "github.copilot.chat.codeGeneration.instructions";
const instructions = Array.isArray(settings[instructionKey]) ? settings[instructionKey] : [];
if (!instructions.some((item) => item && item.file === contextPath)) {
  instructions.push({ file: contextPath });
}
settings[instructionKey] = instructions;
const promptKey = "chat.promptFilesLocations";
settings[promptKey] = settings[promptKey] && typeof settings[promptKey] === "object" && !Array.isArray(settings[promptKey])
  ? settings[promptKey]
  : {};
settings[promptKey][promptsPath] = true;
writeJson(settingsPath, settings);
console.log(`  Updated VS Code settings: ${settingsPath}`);
NODE
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

mkdir -p "$ado_home"
cp "$repo_root/scripts/ado-mcp-launcher.sh" "$launcher_target"
chmod 700 "$launcher_target"

# Always install/update the MCP package globally so the launcher uses the direct
# binary rather than npx. npx has a cold-start delay that causes MCP clients to
# time out during the initialize handshake. Best-effort: warn and continue if
# the global install fails (e.g. EACCES); the launcher will fall back to npx.
echo "Installing @azure-devops/mcp globally..."
npm install -g @azure-devops/mcp --silent || echo "WARN: global npm install failed — launcher will fall back to npx." >&2

existing_docker=""
existing_org=""
if [[ -f "$config_target" ]]; then
  existing_docker="$(json_get "$config_target" "dockerImage" || true)"
  existing_org="$(json_get "$config_target" "organization" || true)"
fi
incoming_docker="$docker_image"
if [[ -f "$config_target" && $force -eq 0 && ( "$existing_docker" != "$incoming_docker" || "$existing_org" != "$organization" ) ]]; then
  echo "Config already exists with different settings. Use --force to overwrite: $config_target" >&2
  exit 1
fi

config_authentication="$authentication"
if [[ -n "$docker_image" ]]; then
  config_authentication="envvar"
fi

node - "$config_target" "$organization" "$config_authentication" "$domains_csv" "$docker_image" <<'NODE'
const fs = require("fs");
const [path, organization, authentication, domainsCsv, dockerImage] = process.argv.slice(2);
const config = {
  organization,
  authentication,
  domains: domainsCsv.split(",").map((item) => item.trim()).filter(Boolean)
};
if (dockerImage) config.dockerImage = dockerImage;
fs.writeFileSync(path, `${JSON.stringify(config, null, 2)}\n`, "utf8");
NODE
echo "Wrote MCP config: $config_target"

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
  "$repo_root/shared/mcp/azure-devops-tools.md" > "$claude_context"

join_sections \
  "$repo_root/plugins/azure-devops-agents-codex/AGENTS.md" \
  "$repo_root/shared/workflows/plan-story.md" \
  "$repo_root/shared/workflows/plan-feature.md" \
  "$repo_root/shared/workflows/plan-epic.md" \
  "$repo_root/shared/mcp/azure-devops-tools.md" > "$codex_context"

join_sections \
  "$repo_root/plugins/azure-devops-agents-vscode/copilot-instructions.md" \
  "$repo_root/shared/workflows/plan-story.md" \
  "$repo_root/shared/workflows/plan-feature.md" \
  "$repo_root/shared/workflows/plan-epic.md" \
  "$repo_root/shared/mcp/azure-devops-tools.md" > "$copilot_context"

if [[ $configure_codex -eq 1 ]]; then
  echo "Configuring Codex..."
  codex_dir="$user_home/.codex"
  write_codex_toml "$codex_dir/config.toml" "$launcher_target" "$force"
  merge_markdown_block "$codex_dir/AGENTS.md" "azure-devops-agents" "$codex_context" "$force"
fi

if [[ $configure_vscode -eq 1 ]]; then
  echo "Configuring VS Code..."
  [[ -d "$prompt_source_dir" ]] || { echo "Prompt source directory not found: $prompt_source_dir" >&2; exit 1; }
  mkdir -p "$prompt_dir"
  cp "$prompt_source_dir"/*.prompt.md "$prompt_dir/"
  cp "$copilot_context" "$copilot_target"
  vs_code_dir="$(vscode_user_dir)"
  merge_vscode_json "$vs_code_dir/mcp.json" "$vs_code_dir/settings.json" "$launcher_target" "$copilot_target" "$prompt_dir" "$force"
fi

claude_mcp_registered=0
claude_plugin_installed=0
if [[ $configure_claude -eq 1 ]]; then
  echo "Configuring Claude Code..."
  if ! command -v claude >/dev/null 2>&1; then
    echo "  Claude CLI not found. Run manually after installing Claude Code:"
    echo "  claude mcp add --scope user azure-devops -- bash \"$launcher_target\""
    echo "  claude plugin marketplace add --scope user \"$repo_root\""
    echo "  claude plugin install --scope user azure-devops-agents-claude@azure-devops-agents"
  else
    claude mcp add --scope user azure-devops -- bash "$launcher_target"
    claude_mcp_registered=1
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
fi

echo
echo "Done. Per-tool summary:"
if [[ $configure_claude -eq 1 ]]; then
  if [[ $claude_mcp_registered -eq 1 && $claude_plugin_installed -eq 1 ]]; then
    echo "  Claude Code : MCP registered + plugin installed + ~/.claude/CLAUDE.md updated"
  else
    echo "  Claude Code : ~/.claude/CLAUDE.md updated (MCP/plugin pending if Claude CLI was absent)"
  fi
fi
[[ $configure_codex -eq 1 ]] && echo "  Codex       : MCP registered + ~/.codex/AGENTS.md updated"
[[ $configure_vscode -eq 1 ]] && echo "  VS Code     : MCP registered + Copilot instruction + prompt files added"
echo
if [[ -n "$docker_image" ]]; then
  echo "Docker auth      : set ADO_MCP_AUTH_TOKEN before starting any tool, or use --auth-token."
else
  echo "Auth defaults to azcli. Run 'az login' if needed."
fi
echo 'Per-repo config  : add .ado-mcp.json -> { "project": "YourProject", "team": "YourTeam" }'
