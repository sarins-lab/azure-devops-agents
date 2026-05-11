# Claude Adapter

Claude Code has two pieces:

- Native plugin package at the repo root: `.claude-plugin/`, `agents/`, and `commands/`
- Packaged Claude skill context under root `skills/azure-devops-planning/`
- Global planning context installed from `plugins/azure-devops-agents-claude/CLAUDE.md`

The installer registers the root marketplace and installs `azure-devops-agents-claude`, then merges this adapter context into `~/.claude/CLAUDE.md`.

The plugin also declares the Azure DevOps MCP server through root `.mcp.json`. That entrypoint runs `scripts/ado-mcp-launcher.mjs`, which starts the PowerShell launcher on Windows and the Bash launcher on macOS/Linux.
