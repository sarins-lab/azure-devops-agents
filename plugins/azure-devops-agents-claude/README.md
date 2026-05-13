# Claude Adapter

Claude Code has two pieces:

- Native plugin package at the repo root: `.claude-plugin/`, `agents/`, and `skills/`
- Packaged Claude skill context under root `skills/azure-devops-planning/`
- Global planning context installed from `plugins/azure-devops-agents-claude/CLAUDE.md`

The repo-local installer registers the root marketplace, installs `azure-devops-agents-claude`, removes any legacy standalone user-scoped Claude MCP server named `azure-devops`, and then merges this adapter context into `~/.claude/CLAUDE.md`.

The Claude plugin owns the MCP declaration through root `.mcp.json`, which launches `scripts/ado-mcp-launcher.mjs`. That dispatcher runs `scripts/ado-mcp-launcher.ps1` on Windows or `scripts/ado-mcp-launcher.sh` on macOS/Linux.
