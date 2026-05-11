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

| Package         | Path                                                                                        | Purpose                                                                            |
| --------------- | ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Claude Code     | `.claude-plugin/`, `commands/`, `agents/`, `skills/`, `plugins/azure-devops-agents-claude/` | Native Claude plugin, commands, agents, skill, MCP declaration, and global context |
| VS Code Copilot | `plugins/azure-devops-agents-vscode/`                                                       | Copilot instruction file and reusable prompt files                                 |
| Codex           | `plugins/azure-devops-agents-codex/`                                                        | Codex plugin manifest, skill, and global `AGENTS.md` adapter                       |

## Package Names

- `azure-devops-agents-claude`
- `azure-devops-agents-vscode`
- `azure-devops-agents-codex`

## Install Behavior

The installers remain shared:

```powershell
.\scripts\install.ps1 -Organization <your-org>
```

```bash
bash ./scripts/install.sh --organization <your-org>
```

It reads the shared core and the three package folders, then writes the correct client-specific files.

Claude Code can also start MCP from the plugin itself:

1. `.claude-plugin/plugin.json` declares `mcpServers: "./.mcp.json"`.
2. `.mcp.json` invokes `node scripts/ado-mcp-launcher.mjs`.
3. The Node dispatcher invokes `scripts/ado-mcp-launcher.ps1` on Windows and `scripts/ado-mcp-launcher.sh` on macOS/Linux.
4. `skills/azure-devops-planning/SKILL.md` ships the planning context that a root `CLAUDE.md` cannot provide during plugin install.

This is the cross-platform plugin-installed path. The MCP server still needs organization/auth configuration from `~/.ado-mcp/config.json`, `ADO_MCP_ORG`, Azure CLI login, service principal variables, or Docker PAT variables.

Codex and VS Code currently do not get arbitrary post-install script execution from these package assets. Their adapters are installed by the shared installer, which writes the MCP server config and planning guidance to the user-level locations those clients already read.

## Publishing Behavior

Claude Code uses the marketplace manifest at `.claude-plugin/marketplace.json`.

Codex uses the marketplace manifest at `.agents/plugins/marketplace.json`.

VS Code Copilot is currently packaged as prompt/instruction assets. A future VSIX extension should use `plugins/azure-devops-agents-vscode/` as its source package and keep `shared/` as the canonical workflow source.

## Adding New Capabilities

When adding a new workflow:

1. Add or update the canonical workflow in `shared/workflows/`.
2. Update tool rules in `shared/mcp/` if needed.
3. Add Claude command or agent changes under `commands/` and `agents/`.
4. Update Claude plugin skill context under `skills/` if the behavior should ship with plugin installation.
5. Add VS Code prompt files under `plugins/azure-devops-agents-vscode/prompts/`.
6. Add Codex skill or adapter guidance under `plugins/azure-devops-agents-codex/`.
7. Run `.\scripts\deploy.ps1` on Windows or `bash ./scripts/deploy.sh` on macOS/Linux.
