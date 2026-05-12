# Plugin Packaging Model

This repo is organized as three client packages over one shared planning core.

## Shared Core

The shared source of truth lives in:

- `shared/workflows/`
- `shared/mcp/`
- `scripts/ado-mcp-launcher.ps1`
- `scripts/ado-mcp-launcher.sh`
- `scripts/ado-mcp-launcher.mjs`
- Docker wrapper files under `docker/`

Client packages should not fork the planning rules. They should consume or package the shared workflows and MCP rules.

## Client Packages

| Package         | Path                                                                           | Purpose                                                                  |
| --------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| Claude Code     | `.claude-plugin/`, `agents/`, `skills/`, `plugins/azure-devops-agents-claude/` | Native Claude plugin, agents, skill, MCP declaration, and global context |
| VS Code Copilot | `plugins/azure-devops-agents-vscode/`                                          | Copilot instruction file                                                 |
| Codex           | `plugins/azure-devops-agents-codex/`                                           | Codex plugin manifest, skill, and global `AGENTS.md` adapter             |

## Package Names

- `azure-devops-agents-claude`
- `azure-devops-agents-vscode`
- `azure-devops-agents-codex`

## Install Behavior

### Online installer

`scripts/install-online.ps1` is the full public, clone-free Windows PowerShell
installer. It is designed for direct online execution:

```powershell
$env:ADO_MCP_ORG = "<your-org>"
irm https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main/scripts/install-online.ps1 | iex
```

A TinyURL for PowerShell should redirect to:

```text
https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main/scripts/install-online.ps1
```

`scripts/install-online.sh` is the matching self-contained macOS/Linux
installer:

```bash
export ADO_MCP_ORG="<your-org>"
curl -fsSL https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main/scripts/install-online.sh | bash
```

A TinyURL for macOS/Linux should redirect to:

```text
https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main/scripts/install-online.sh
```

The PowerShell installer can also be invoked with explicit parameters:

```powershell
$install = Invoke-RestMethod https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main/scripts/install-online.ps1
& ([scriptblock]::Create($install)) -Organization <your-org>
```

It is intentionally self-contained. It embeds the PowerShell MCP launcher and the
Codex, VS Code, and Claude planning context, then writes the same user-level MCP
configuration that the repo-local installer writes. It does not download this
repository, clone it, or unpack a release archive.

The Bash installer writes the Bash MCP launcher and the user-level Codex, VS
Code, and Claude context without reading files from a local clone.

The online installer does not install the native Claude plugin package because
Claude marketplace installs require a local plugin directory. It still registers
the Claude MCP server when the Claude CLI is available and writes global Claude
context.

### Repo-local installer

The repo-local installers remain shared:

```powershell
.\scripts\install.ps1 -Organization <your-org>
```

```bash
bash ./scripts/install.sh --organization <your-org>
```

It reads the shared core and the three package folders, then writes the correct client-specific files.

Claude Code uses a plugin-owned MCP model:

1. `.claude-plugin/plugin.json` points Claude at root `.mcp.json` through `mcpServers`.
2. Root `.mcp.json` launches `scripts/ado-mcp-launcher.mjs` from `${CLAUDE_PLUGIN_ROOT}`.
3. `scripts/ado-mcp-launcher.mjs` dispatches to `scripts/ado-mcp-launcher.ps1` on Windows or `scripts/ado-mcp-launcher.sh` on macOS/Linux.
4. The repo-local installer registers the marketplace, installs `azure-devops-agents-claude`, removes any legacy standalone user-scoped MCP entry, and merges global planning context into `~/.claude/CLAUDE.md`.
5. `skills/azure-devops-planning/SKILL.md` ships the planning context that a root `CLAUDE.md` cannot provide during plugin install.

This keeps Claude on a single MCP declaration path owned by the plugin while still using `~/.ado-mcp/config.json`, `ADO_MCP_ORG`, Azure CLI login, service principal variables, or Docker PAT variables for runtime configuration.

Codex and VS Code currently do not get arbitrary post-install script execution from these package assets. Their adapters are installed by the shared installer, which writes the MCP server config and planning guidance to the user-level locations those clients already read.

## Publishing Behavior

Claude Code uses the marketplace manifest at `.claude-plugin/marketplace.json`.

Codex uses the marketplace manifest at `.agents/plugins/marketplace.json`.

VS Code Copilot is currently packaged as an instruction asset. A future VSIX extension should use `plugins/azure-devops-agents-vscode/` as its source package and keep `shared/` as the canonical workflow source.

## Adding New Capabilities

When adding a new workflow:

1. Add or update the canonical workflow in `shared/workflows/`.
2. Update tool rules in `shared/mcp/` if needed.
3. Add Claude agent changes under `agents/` when a new role is needed.
4. Update Claude plugin skill context under `skills/` if the behavior should ship with plugin installation.
5. Update VS Code guidance in `plugins/azure-devops-agents-vscode/copilot-instructions.md`.
6. Add Codex skill or adapter guidance under `plugins/azure-devops-agents-codex/`.
7. Run `.\scripts\deploy.ps1` on Windows or `bash ./scripts/deploy.sh` on macOS/Linux.
