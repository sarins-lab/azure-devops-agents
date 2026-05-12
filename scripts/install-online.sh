#!/usr/bin/env bash
set -euo pipefail

organization="${ADO_MCP_ORG:-}"
authentication="${ADO_MCP_AUTHENTICATION:-azcli}"
domains_csv="${ADO_MCP_DOMAINS:-core,work,work-items,repositories,wiki}"
docker_image="${ADO_MCP_DOCKER_IMAGE:-}"
auth_token=""
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
prompt_dir="$ado_home/prompts"

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
  local prompts_path="$5"
  local force_flag="$6"
  require_node
  mkdir -p "$(dirname "$mcp_path")" "$(dirname "$settings_path")"
  node - "$mcp_path" "$settings_path" "$launcher_path" "$context_path" "$prompts_path" "$force_flag" <<'NODE'
const fs = require("fs");
const [mcpPath, settingsPath, launcherPath, contextPath, promptsPath, forceFlag] = process.argv.slice(2);
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

tmp_dir="$(mktemp -d)"
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

project=""
team=""
if [[ -n "$repo_config_path" ]]; then
  project="$(json_value "$repo_config_path" "project" | head -n 1 || true)"
  team="$(json_value "$repo_config_path" "team" | head -n 1 || true)"
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
LAUNCHER
chmod 700 "$launcher_target"
echo "Wrote online MCP launcher: $launcher_target"

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

require_node
node - "$config_target" "$organization" "$config_authentication" "$domains_csv" "$docker_image" <<'NODE'
const fs = require("fs");
const [path, organization, authentication, domainsCsv, dockerImage] = process.argv.slice(2);
const config = {
  organization,
  authentication,
  domains: domainsCsv.split(",").map((item) => item.trim()).filter(Boolean)
};
if (dockerImage) config.dockerImage = dockerImage;
fs.mkdirSync(require("path").dirname(path), { recursive: true });
fs.writeFileSync(path, `${JSON.stringify(config, null, 2)}\n`, "utf8");
NODE
echo "Wrote MCP config: $config_target"

if [[ -n "$docker_image" && -n "$auth_token" ]]; then
  printf 'export ADO_MCP_AUTH_TOKEN=%s\n' "$(shell_quote "$auth_token")" > "$env_target"
  chmod 600 "$env_target"
  export ADO_MCP_AUTH_TOKEN="$auth_token"
  echo "Stored ADO_MCP_AUTH_TOKEN in $env_target for Docker MCP mode."
fi

cat > "$codex_context" <<'EOF'
# Azure DevOps - Sprint Planning (azure-devops-agents)

The `azure-devops` MCP server is configured at user level via `~/.codex/config.toml`.
Place `.ado-mcp.json` in any repo root to specify `project` and `team`; the launcher injects them automatically.

Epic -> Feature -> User Story -> Task

All items must be created with parent links. Never leave a work item parentless.

Run the planning workflow automatically when planning intent is detected. Also recognize `/plan-story`, `/plan-feature`, and `/plan-epic` as routing instructions. Do not create Azure DevOps work items until the user confirms the plan.

# plan-story

Create one Azure DevOps User Story under an existing Feature.

1. Load context. If the prompt contains `under feature <id>`, call `mcp_ado_wit_get_work_item` for that Feature. If no Feature ID is specified, ask for the ADO Feature ID before creating anything.
2. BA phase. Draft one story in `As a [persona] I want [goal] so that [value]` format with 2-4 Given/When/Then acceptance criteria and an explicit out-of-scope boundary. Pause for confirmation.
3. SA phase. Add one implementation note covering what changes, which service owns it, how it integrates, and the key technical decision. Pause for confirmation.
4. PM phase. Estimate Fibonacci story points, recommend a sprint using `mcp_ado_work_list_team_iterations` and `mcp_ado_work_get_team_capacity`, and flag if the story should be split. Pause before creating anything in ADO.
5. Create after confirmation with `mcp_ado_wit_add_child_work_items` under the Feature, then use `mcp_ado_wit_update_work_item` for Acceptance Criteria and Story Points.
6. Read back with `mcp_ado_wit_get_work_item`. If the parent link is missing, call `mcp_ado_wit_work_items_link`.

# plan-feature

Run the BA, SA, Architect, and PM planning flow for one Feature, then create linked Azure DevOps work items.

1. Load context. If a Feature ID is provided, call `mcp_ado_wit_get_work_item` for the Feature and parent Epic. If only a description is provided, ask for the parent Epic ID before creating anything.
2. BA phase. Decompose the Feature into 2-6 User Stories with Given/When/Then acceptance criteria and explicit out-of-scope boundaries. Pause for confirmation.
3. SA phase. Produce a feature-level technical design and per-story implementation notes. Ground the design with official repo tools. Pause for confirmation.
4. Architect phase. Read prior ADR context with wiki tools. Write ADRs for significant decisions and audit cross-cutting concerns. Pause for confirmation.
5. PM phase. Estimate story points, order by dependency and value, and assign stories to sprints using team iteration and capacity tools. Pause before creating anything in ADO.
6. Create parent-before-child with `mcp_ado_wit_add_child_work_items`; enrich fields with `mcp_ado_wit_update_work_item`; verify every link.

# plan-epic

Run the full BA, SA, Architect, and PM planning flow for an Epic, then create linked Azure DevOps Features, User Stories, and ADR pages.

1. Load context. If an Epic ID is provided, call `mcp_ado_wit_get_work_item` for the Epic. If only a description is provided, ask whether to create a new Epic or plan against an existing Epic.
2. BA phase. Decompose the Epic into Features and User Stories with Given/When/Then acceptance criteria. Pause for confirmation.
3. SA phase. Add technical design to each Feature and implementation notes to each Story. Ground the design in repositories using official repo tools. Pause for confirmation.
4. Architect phase. Read existing ADRs with the wiki tool sequence. Write new ADRs and cross-cutting concern findings. Pause for confirmation.
5. PM phase. Estimate story points, order by dependency and value, and assign stories to sprints. Pause before creating anything in ADO.
6. Create items parent-before-child, then verify traceability with `mcp_ado_wit_get_work_item`.

# Azure DevOps MCP Tooling

Use Microsoft's official `@azure-devops/mcp` package through the `azure-devops` MCP server.

Tool names use the `mcp_ado_*` naming pattern.

`mcp_ado_wit_add_child_work_items` creates child work items and parent links. It supports title, description, area path, iteration path, and Markdown/HTML format.

It does not set fields such as Acceptance Criteria, Story Points, or Tags. Add those afterward with `mcp_ado_wit_update_work_item`.

Use `mcp_ado_wit_work_items_link` only to repair or add links after creation.

For backlog lookup, call `mcp_ado_wit_list_backlogs` first, then call `mcp_ado_wit_list_backlog_work_items` with `project`, `team`, and `backlogId`.

For wiki lookup, use `mcp_ado_wiki_list_wikis`, `mcp_ado_wiki_list_pages`, `mcp_ado_wiki_get_page`, and `mcp_ado_wiki_get_page_content`.
EOF

cat > "$claude_context" <<'EOF'
# Azure DevOps - Sprint Planning (azure-devops-agents)

Use the `azure-devops` MCP server for Azure DevOps planning work. Place `.ado-mcp.json` in any repo root to specify `project` and `team`; the launcher injects them automatically.

Epic -> Feature -> User Story -> Task

Pause for user confirmation after each planning phase. Never create Azure DevOps work items until the user confirms the plan.

Use Microsoft's official `@azure-devops/mcp` package. Tool names use the `mcp_ado_*` naming pattern.
EOF

cat > "$copilot_context" <<'EOF'
# Azure DevOps Sprint Planning

Use the `azure-devops` MCP server for all Azure DevOps operations. The launcher reads `.ado-mcp.json` from the repo root to determine project and team automatically.

Epic -> Feature -> User Story -> Task

Always create items with parent links. Never leave a work item parentless. Recognize `/plan-epic`, `/plan-feature`, `/plan-story`, and natural planning intent.

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
  mkdir -p "$prompt_dir"
  cp "$copilot_context" "$copilot_target"
  cat > "$prompt_dir/plan-story.prompt.md" <<'EOF'
---
name: plan-story
description: Create one Azure DevOps user story with acceptance criteria, implementation notes, estimate, sprint recommendation, and parent traceability.
argument-hint: <story-description> [under feature <feature-id>]
tools: ["azure-devops/*"]
---

Create a single well-formed Azure DevOps User Story under the specified Feature. Follow the embedded plan-story workflow from the Azure DevOps Sprint Planning context. Do not create anything until the user confirms.
EOF
  cat > "$prompt_dir/plan-feature.prompt.md" <<'EOF'
---
name: plan-feature
description: Plan one Azure DevOps feature with stories, implementation notes, ADR guidance, estimate, sprint assignment, and traceability.
argument-hint: <feature-id or feature-description> [under epic <epic-id>]
tools: ["azure-devops/*"]
---

Plan a feature using BA, SA, Architect, and PM phases. Follow the embedded plan-feature workflow from the Azure DevOps Sprint Planning context. Do not create anything until the user confirms.
EOF
  cat > "$prompt_dir/plan-epic.prompt.md" <<'EOF'
---
name: plan-epic
description: Plan one Azure DevOps epic with features, stories, ADR guidance, estimates, sprint assignment, and traceability.
argument-hint: <epic-id or epic-description>
tools: ["azure-devops/*"]
---

Plan an epic using BA, SA, Architect, and PM phases. Follow the embedded plan-epic workflow from the Azure DevOps Sprint Planning context. Do not create anything until the user confirms.
EOF

  vs_code_dir="$(vscode_user_dir)"
  merge_vscode_json "$vs_code_dir/mcp.json" "$vs_code_dir/settings.json" "$launcher_target" "$copilot_target" "$prompt_dir" "$force"
fi

claude_mcp_registered=0
if [[ $configure_claude -eq 1 ]]; then
  echo "Configuring Claude Code..."
  if ! command -v claude >/dev/null 2>&1; then
    echo "  Claude CLI not found. Run manually after installing Claude Code:"
    echo "  claude mcp add --scope user azure-devops -- bash \"$launcher_target\""
  else
    claude mcp add --scope user azure-devops -- bash "$launcher_target"
    claude_mcp_registered=1
  fi
  merge_markdown_block "$user_home/.claude/CLAUDE.md" "azure-devops-agents" "$claude_context" "$force"
fi

echo
echo "Done. Per-tool summary:"
if [[ $configure_claude -eq 1 ]]; then
  if [[ $claude_mcp_registered -eq 1 ]]; then
    echo "  Claude Code : MCP registered + ~/.claude/CLAUDE.md updated"
  else
    echo "  Claude Code : ~/.claude/CLAUDE.md updated (MCP registration pending if Claude CLI was absent)"
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
