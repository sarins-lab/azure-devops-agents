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

clients_csv="All"
purge_global=0

usage() {
  printf '%s\n' \
    "Usage:" \
    "  ./scripts/uninstall.sh [options]" \
    "" \
    "Options:" \
    "  --clients <csv>   All, Claude, VSCode, Codex. Default: All." \
    "  --purge-global    Also uninstall the global @azure-devops/mcp npm package." \
    "  -h, --help        Show this help."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clients)
      if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
        echo "Missing value for --clients." >&2
        usage >&2
        exit 1
      fi
      clients_csv="${2:-}"
      shift 2
      ;;
    --purge-global)
      purge_global=1
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
    codex)    configure_codex=1 ;;
    claude)   configure_claude=1 ;;
    vscode|vs-code|copilot) configure_vscode=1 ;;
    "") ;;
    *)
      echo "Unknown client: $client" >&2
      exit 1
      ;;
  esac
done

user_home="${ADO_MCP_HOME:-$HOME}"
ado_home="$user_home/.ado-mcp"

# Remove a <!-- marker: start --> ... <!-- marker: end --> block from a file.
# Skips gracefully if Node.js is not available.
remove_markdown_block() {
  local path="$1"
  local marker="$2"
  [[ -f "$path" ]] || return 0
  if ! command -v node >/dev/null 2>&1; then
    echo "  WARN: Node.js not found — cannot remove block from $path. Remove manually." >&2
    return 0
  fi
  node - "$path" "$marker" <<'NODE'
const fs = require("fs");
const [path, marker] = process.argv.slice(2);
const start = `<!-- ${marker}: start -->`;
const end   = `<!-- ${marker}: end -->`;
// Normalise CRLF so the regex works regardless of line endings.
let text = fs.readFileSync(path, "utf8").replace(/\r\n/g, "\n");
if (!text.includes(start)) {
  console.log(`  Block not found, nothing to remove: ${path}`);
  process.exit(0);
}
const escapedStart = start.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const escapedEnd   = end.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
text = text.replace(new RegExp(`\\n?${escapedStart}[\\s\\S]*?${escapedEnd}\\n?`, "g"), "\n");
const trimmed = text.replace(/\n{3,}/g, "\n\n").trimEnd();
text = trimmed !== "" ? trimmed + "\n" : "";
fs.writeFileSync(path, text, "utf8");
console.log(`  Removed block from: ${path}`);
NODE
}

remove_claude_user_mcp_server() {
  local list_output line name output
  local removed=0
  local failed=0

  if ! list_output="$(claude mcp list 2>&1)"; then
    printf '%s\n' "$list_output" >&2
    echo "  WARN: could not remove standalone Claude MCP server registrations." >&2
    return 0
  fi

  while IFS= read -r line; do
    [[ "$line" =~ \.ado-mcp[\\/](ado-mcp|ado-mcp-launcher)\.(sh|ps1) ]] || continue
    name="${line%%:*}"
    [[ -n "$name" ]] || continue

    if output="$(claude mcp remove --scope user "$name" 2>&1)"; then
      echo "  Removed standalone Claude MCP server: $name"
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
    echo "  WARN: could not remove standalone Claude MCP server registrations." >&2
    return 0
  fi

  if (( removed != 0 )); then
    echo "  Removed standalone Claude MCP server registrations."
  else
    echo "  Standalone Claude MCP servers not registered, skipping."
  fi

  return 0
}

vscode_user_dir() {
  case "$(uname -s)" in
    Darwin) printf '%s\n' "$HOME/Library/Application Support/Code/User" ;;
    Linux)  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User" ;;
    *)
      echo "Unsupported OS: $(uname -s)" >&2
      exit 1
      ;;
  esac
}

# ── Claude Code ────────────────────────────────────────────────────────────────
if [[ $configure_claude -eq 1 ]]; then
  echo "Removing Claude Code configuration..."

  if command -v claude >/dev/null 2>&1; then
    remove_claude_user_mcp_server

    if claude plugin list 2>/dev/null | grep -Eq "azure-devops-agents-claude@azure-devops-agents"; then
      if output="$(claude plugin uninstall --scope user azure-devops-agents-claude@azure-devops-agents 2>&1)"; then
        echo "  Uninstalled plugin: azure-devops-agents-claude"
      else
        printf '%s\n' "$output" >&2
        echo "  WARN: could not uninstall plugin: azure-devops-agents-claude" >&2
      fi
    else
      echo "  Plugin not installed, skipping."
    fi

    if claude plugin marketplace list 2>/dev/null | grep -Eq "azure-devops-agents"; then
      if output="$(claude plugin marketplace remove --scope user azure-devops-agents 2>&1)"; then
        echo "  Removed marketplace: azure-devops-agents"
      else
        printf '%s\n' "$output" >&2
        echo "  WARN: could not remove marketplace: azure-devops-agents" >&2
      fi
    else
      echo "  Marketplace not registered, skipping."
    fi
  else
    echo "  Claude CLI not found — skipping MCP/plugin removal."
  fi

  remove_markdown_block "$user_home/.claude/CLAUDE.md" "azure-devops-agents"

  # Remove the disabledMcpjsonServers entry added by the installer.
  claude_settings="$user_home/.claude/settings.json"
  if [[ -f "$claude_settings" ]]; then
    if ! command -v node >/dev/null 2>&1; then
      echo "  WARN: Node.js not found — cannot update $claude_settings. Remove disabledMcpjsonServers manually." >&2
    else
      node - "$claude_settings" <<'NODE'
const fs = require("fs");
const settingsPath = process.argv[2];
let json = {};
try {
  const raw = fs.readFileSync(settingsPath, "utf8").trim();
  if (raw) json = JSON.parse(raw);
} catch (err) {
  console.error(`  WARN: Could not parse ${settingsPath} — remove disabledMcpjsonServers manually. (${err.message})`);
  process.exit(0);
}
if (!Array.isArray(json.disabledMcpjsonServers)) {
  console.log(`  disabledMcpjsonServers not present, skipping: ${settingsPath}`);
  process.exit(0);
}
const filtered = json.disabledMcpjsonServers.filter((s) => s !== "azure-devops");
if (filtered.length === 0) {
  delete json.disabledMcpjsonServers;
} else {
  json.disabledMcpjsonServers = filtered;
}
fs.writeFileSync(settingsPath, JSON.stringify(json, null, 2) + "\n", "utf8");
console.log(`  Removed 'azure-devops' from disabledMcpjsonServers: ${settingsPath}`);
NODE
    fi
  else
    echo "  Claude settings.json not found, skipping."
  fi
fi

# ── VS Code / Copilot ──────────────────────────────────────────────────────────
if [[ $configure_vscode -eq 1 ]]; then
  echo "Removing VS Code configuration..."
  vs_code_dir="$(vscode_user_dir)"
  mcp_path="$vs_code_dir/mcp.json"
  settings_path="$vs_code_dir/settings.json"
  copilot_context="$ado_home/copilot-context.md"
  prompt_dir="$ado_home/prompts"

  if [[ -f "$mcp_path" ]]; then
    if ! command -v node >/dev/null 2>&1; then
      echo "  WARN: Node.js not found — cannot update $mcp_path. Remove azure-devops entry manually." >&2
    else
      node - "$mcp_path" <<'NODE'
const fs = require("fs");
const path = process.argv[2];
let mcp;
try {
  mcp = JSON.parse(fs.readFileSync(path, "utf8"));
} catch (err) {
  console.error(`  WARN: Could not parse ${path} — skipping MCP update. Remove azure-devops entry manually. (${err.message})`);
  process.exit(0);
}
if (mcp.servers && mcp.servers["azure-devops"]) {
  delete mcp.servers["azure-devops"];
  fs.writeFileSync(path, JSON.stringify(mcp, null, 2) + "\n", "utf8");
  console.log(`  Removed azure-devops from: ${path}`);
} else {
  console.log(`  azure-devops not found in: ${path}`);
}
NODE
    fi
  else
    echo "  VS Code mcp.json not found, skipping."
  fi

  if [[ -f "$settings_path" ]]; then
    if ! command -v node >/dev/null 2>&1; then
      echo "  WARN: Node.js not found — cannot update $settings_path. Remove azure-devops entries manually." >&2
    else
      node - "$settings_path" "$copilot_context" "$prompt_dir" <<'NODE'
const fs = require("fs");
const [settingsPath, contextPath, promptsPath] = process.argv.slice(2);

// VS Code settings.json is JSONC — strip // line comments, /* block comments */,
// and trailing commas before parsing so we don't abort on a common file format.
function stripJsonc(text) {
  let out = "", inStr = false, escaped = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i], next = text[i + 1];
    if (escaped)            { out += ch; escaped = false; continue; }
    if (inStr && ch === "\\") { out += ch; escaped = true; continue; }
    if (ch === '"')           { inStr = !inStr; out += ch; continue; }
    if (inStr)                { out += ch; continue; }
    if (ch === "/" && next === "/") { while (i < text.length && text[i] !== "\n") i++; continue; }
    if (ch === "/" && next === "*") { i += 2; while (i < text.length && !(text[i] === "*" && text[i+1] === "/")) i++; i++; continue; }
    out += ch;
  }
  return out.replace(/,(\s*[}\]])/g, "$1");
}

let settings;
try {
  settings = JSON.parse(stripJsonc(fs.readFileSync(settingsPath, "utf8")));
} catch (err) {
  console.error(`  WARN: Could not parse ${settingsPath} — skipping settings update. Remove azure-devops entries manually. (${err.message})`);
  process.exit(0);
}

const instructionKey = "github.copilot.chat.codeGeneration.instructions";
let changed = false;
if (Array.isArray(settings[instructionKey])) {
  const filtered = settings[instructionKey].filter(
    (item) => !item || item.file !== contextPath
  );
  if (filtered.length !== settings[instructionKey].length) {
    changed = true;
    if (filtered.length === 0) {
      delete settings[instructionKey];
    } else {
      settings[instructionKey] = filtered;
    }
  }
}

const promptKey = "chat.promptFilesLocations";
if (settings[promptKey] && typeof settings[promptKey] === "object") {
  if (Object.prototype.hasOwnProperty.call(settings[promptKey], promptsPath)) {
    delete settings[promptKey][promptsPath];
    changed = true;
    if (Object.keys(settings[promptKey]).length === 0) delete settings[promptKey];
  }
}

if (changed) {
  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n", "utf8");
  console.log(`  Updated VS Code settings: ${settingsPath}`);
} else {
  console.log(`  VS Code settings already clean: ${settingsPath}`);
}
NODE
    fi
  else
    echo "  VS Code settings.json not found, skipping."
  fi

  [[ -f "$copilot_context" ]] && rm -f "$copilot_context" && echo "  Removed: $copilot_context"
  [[ -d "$prompt_dir" ]] && rm -rf "$prompt_dir" && echo "  Removed: $prompt_dir"
fi

# ── Codex ──────────────────────────────────────────────────────────────────────
if [[ $configure_codex -eq 1 ]]; then
  echo "Removing Codex configuration..."
  codex_toml="$user_home/.codex/config.toml"

  if [[ -f "$codex_toml" ]]; then
    if ! command -v node >/dev/null 2>&1; then
      echo "  WARN: Node.js not found — cannot update $codex_toml. Remove [mcp_servers.azure-devops] manually." >&2
    else
      node - "$codex_toml" <<'NODE'
const fs = require("fs");
const path = process.argv[2];
let text = fs.readFileSync(path, "utf8");
if (/^\[mcp_servers\.azure-devops\]/m.test(text)) {
  text = text.replace(/\n?\[mcp_servers\.azure-devops\]\r?\n[\s\S]*?(?=\n\[|\s*$)/, "");
  fs.writeFileSync(path, text, "utf8");
  console.log(`  Removed [mcp_servers.azure-devops] from: ${path}`);
} else {
  console.log(`  [mcp_servers.azure-devops] not found in: ${path}`);
}
NODE
    fi
  else
    echo "  Codex config.toml not found, skipping."
  fi

  remove_markdown_block "$user_home/.codex/AGENTS.md" "azure-devops-agents"
fi

# ── Shared ~/.ado-mcp directory ────────────────────────────────────────────────
# Only remove if all three clients were uninstalled (full removal).
if [[ $configure_claude -eq 1 && $configure_vscode -eq 1 && $configure_codex -eq 1 ]]; then
  if [[ -d "$ado_home" ]]; then
    rm -rf "$ado_home"
    echo "Removed: $ado_home"
  fi
fi

# ── Optional: global npm package ──────────────────────────────────────────────
if [[ $purge_global -eq 1 ]]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "WARN: npm not found — cannot uninstall global package." >&2
  else
    if npm uninstall -g @azure-devops/mcp; then
      echo "Removed global package if present: @azure-devops/mcp"
    else
      echo "WARN: global npm uninstall failed for @azure-devops/mcp." >&2
    fi
  fi
fi

echo
echo "Done. Uninstall complete."
