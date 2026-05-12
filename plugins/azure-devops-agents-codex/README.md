# Codex Adapter

`AGENTS.md` is merged into `~/.codex/AGENTS.md` by the installer.

Codex does not load Claude slash command files, so this adapter treats the preferred RUP routes as instruction routes. The canonical workflow is appended from `shared/workflows/rup-planning.md`.

The shared installer registers the Azure DevOps MCP server in `~/.codex/config.toml`. On Windows it points to the PowerShell launcher; on macOS/Linux it points to the Bash launcher.
