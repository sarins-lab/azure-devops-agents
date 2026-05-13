# Client Adapters

This directory contains the client-specific packaging layer for the Azure DevOps planning workflows.

| Adapter | Files | Install target |
| ------- | ----- | -------------- |
| Claude Code | `plugins/azure-devops-agents-claude/` plus root `.claude-plugin/`, `agents/`, and `skills/` | Claude plugin discovery, plugin-owned MCP, skill context, and `~/.claude/CLAUDE.md` |
| VS Code Copilot | `plugins/azure-devops-agents-vscode/` | `~/.ado-mcp/copilot-context.md` |
| Codex | `plugins/azure-devops-agents-codex/` | `~/.codex/AGENTS.md` |

Keep canonical behavior in `shared/`. Adapter files should translate that behavior into the conventions each client understands.

Claude Code marketplace metadata lives in root `.claude-plugin/marketplace.json` because Claude expects marketplace manifests under `.claude-plugin/` at the marketplace root.

The shared repo-local installers are `scripts/install.ps1` for Windows and `scripts/install.sh` for macOS/Linux. For Claude Code they register the marketplace, install the plugin, and rely on root `.mcp.json` plus `scripts/ado-mcp-launcher.mjs` for the plugin-owned MCP server.

See `docs/plugin-packaging.MD` for the package naming and release model.
