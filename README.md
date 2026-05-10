# azure-devops-agents

A Claude Code plugin that runs a **BA → SA → Architect → PM multi-agent pipeline** to decompose epics into fully traced, estimated user stories and Architecture Decision Records, then creates everything in Azure DevOps.

## What this is

Most teams use an AI assistant as a single generalist. This plugin instead structures sprint planning as a chain of four specialists, each with a narrow role and explicit output contract that the next agent parses:

| Agent | Role |
|-------|------|
| **BA** | Decomposes epics and features into user stories with Given/When/Then acceptance criteria, INVEST validation, and out-of-scope boundaries |
| **SA** | Produces a feature-level technical design, per-story implementation notes, dependency-ordered build sequence, and a risk register |
| **Architect** | Writes ADRs for significant decisions, audits 19 cross-cutting concerns (auth, mTLS, secrets, observability, resilience…), flags principle violations |
| **PM** | Estimates story points on the Fibonacci scale, splits oversized stories, assigns work to sprints based on live team capacity from Azure DevOps |

Each command pauses for your confirmation at the end of each phase before proceeding.

## Works with

- **Claude Code** (CLI and desktop)
- **VS Code** (GitHub Copilot with MCP support)
- **OpenAI Codex**

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and signed in
- Node.js 18+ (for `npx @azure-devops/mcp`)
- Claude Code, VS Code, or Codex

## Setup

### 1 — Sign in to Azure CLI

```powershell
az login

# Recommended on Windows: silent SSO via Windows broker
az config set core.enable_broker_on_windows=true
```

### 2 — Run the installer

The installer registers the `azure-devops` MCP server in Claude Code, VS Code, and Codex. Run it once — it works across all repos.

```powershell
.\scripts\install-ado-mcp-user.ps1 -Organization <your-ado-org>
```

To configure specific clients only:

```powershell
.\scripts\install-ado-mcp-user.ps1 -Organization <your-ado-org> -ConfigureClaude
.\scripts\install-ado-mcp-user.ps1 -Organization <your-ado-org> -ConfigureVSCode
.\scripts\install-ado-mcp-user.ps1 -Organization <your-ado-org> -ConfigureCodex
```

The installer writes:
- `~/.ado-mcp/ado-mcp.ps1` — launcher script
- `~/.ado-mcp/config.json` — your org and auth method
- MCP entries in Claude Code, VS Code user config, and Codex

### 3 — Add a repo config

In each repo that uses Azure DevOps, add `.ado-mcp.json` to the root:

```json
{
  "project": "YourProject",
  "team": "YourTeam"
}
```

The launcher reads this file automatically when any tool spawns the MCP server. No changes to user-level config are needed when switching repos.

### 4 — Load the plugin in Claude Code

```bash
# From within the azure-devops-agents directory
claude
```

Claude Code auto-discovers `.claude-plugin/plugin.json` and loads the agents and commands.

## Commands

| Command | What it does |
|---------|-------------|
| `/plan-epic <id or description>` | Full BA → SA → Architect → PM pipeline for an epic. Creates features, stories, and ADRs in Azure DevOps. |
| `/plan-feature <id or description>` | Same pipeline scoped to a single feature. |
| `/plan-story <description> [under feature <id>]` | Creates one user story with AC, SA notes, and a Fibonacci story point estimate. |

## How the MCP launcher works

Rather than hardcoding an ADO project in user-level config, the launcher (`~/.ado-mcp/ado-mcp.ps1`) walks up the directory tree from the current working directory at startup, finds the nearest `.ado-mcp.json`, and injects `ado_mcp_project` and `ado_mcp_team` as environment variables before spawning `npx @azure-devops/mcp`. The org and auth method stay in the user-level `~/.ado-mcp/config.json` and never need to change.

## Authentication

The default authentication method is `azcli` — the launcher uses your active `az login` session. No service principal is required for personal or team use.

If you need unattended/CI authentication, set these environment variables and re-run the installer:

```powershell
[Environment]::SetEnvironmentVariable("AZURE_CLIENT_ID",     "<id>",     "User")
[Environment]::SetEnvironmentVariable("AZURE_CLIENT_SECRET", "<secret>", "User")
[Environment]::SetEnvironmentVariable("AZURE_TENANT_ID",     "<tenant>", "User")
```

The launcher detects these variables and performs a service principal login before starting the MCP server.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[AGPL-3.0](LICENSE)
