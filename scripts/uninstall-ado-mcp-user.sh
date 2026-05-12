#!/usr/bin/env bash
set -euo pipefail

clients_csv="All"
purge_global=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/uninstall.sh [options]

Options:
  --clients <csv>   All, Claude, VSCode, Codex. Default: All.
  --purge-global    Also uninstall the global @azure-devops/mcp npm package.
  -h, --help        Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clients)
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
text = text.replace(new RegExp(`\\n?${escapedStart}[\\s\\S]*?${escapedEnd}\\n?`), "\n");
text = text.replace(/\n{3,}/g, "\n\n").trimEnd() + (text.trimEnd() !== "" ? "\n" : "");
fs.writeFileSync(path, text, "utf8");
console.log(`  Removed block from: ${path}`);
NODE
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
    if claude mcp list 2>/dev/null | grep -q "azure-devops"; then
      claude mcp remove --scope user azure-devops
      echo "  Removed MCP server: azure-devops"
    else
      echo "  MCP server not registered, skipping."
    fi

    if claude plugin list 2>/dev/null | grep -Eq "azure-devops-agents-claude@azure-devops-agents"; then
      claude plugin uninstall --scope user azure-devops-agents-claude@azure-devops-agents
      echo "  Uninstalled plugin: azure-devops-agents-claude"
    else
      echo "  Plugin not installed, skipping."
    fi

    if claude plugin marketplace list 2>/dev/null | grep -Eq "azure-devops-agents"; then
      claude plugin marketplace remove --scope user azure-devops-agents
      echo "  Removed marketplace: azure-devops-agents"
    else
      echo "  Marketplace not registered, skipping."
    fi
  else
    echo "  Claude CLI not found — skipping MCP/plugin removal."
  fi

  remove_markdown_block "$user_home/.claude/CLAUDE.md" "azure-devops-agents"
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
const mcp = JSON.parse(fs.readFileSync(path, "utf8"));
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
const settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));

const instructionKey = "github.copilot.chat.codeGeneration.instructions";
if (Array.isArray(settings[instructionKey])) {
  settings[instructionKey] = settings[instructionKey].filter(
    (item) => !item || item.file !== contextPath
  );
  if (settings[instructionKey].length === 0) delete settings[instructionKey];
}

const promptKey = "chat.promptFilesLocations";
if (settings[promptKey] && typeof settings[promptKey] === "object") {
  delete settings[promptKey][promptsPath];
  if (Object.keys(settings[promptKey]).length === 0) delete settings[promptKey];
}

fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n", "utf8");
console.log(`  Updated VS Code settings: ${settingsPath}`);
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
  if npm ls -g --depth=0 @azure-devops/mcp >/dev/null 2>&1; then
    npm uninstall -g @azure-devops/mcp
    echo "Uninstalled global package: @azure-devops/mcp"
  else
    echo "Global package @azure-devops/mcp not installed, skipping."
  fi
fi

echo
echo "Done. Uninstall complete."
