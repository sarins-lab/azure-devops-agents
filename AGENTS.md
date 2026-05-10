# azure-devops-agents — Codex context

This repo is a multi-agent sprint planning plugin for Azure DevOps, designed for Claude Code, VS Code, and Codex.

## MCP server

The `azure-devops` MCP server is configured in `~/.codex/config.toml` and backed by `~/.ado-mcp/ado-mcp.ps1`. The launcher reads `.ado-mcp.json` from the repo root and automatically sets the ADO project. No manual project override is needed.

Run `.\scripts\install-ado-mcp-user.ps1 -Organization <your-org>` once to configure the MCP for all tools.

## Agents

| Agent | File | Role |
|-------|------|------|
| BA | `agents/ba-agent.md` | User stories with Given/When/Then acceptance criteria |
| SA | `agents/sa-agent.md` | Technical design, dependency order, risk register |
| Architect | `agents/architect-agent.md` | ADRs, cross-cutting concern audit, principle violations |
| PM | `agents/pm-agent.md` | Fibonacci estimates, story splitting, sprint assignment |

## Commands

- `plan-epic` — Full BA → SA → Architect → PM pipeline for an epic
- `plan-feature` — Same pipeline scoped to one feature
- `plan-story` — Single user story with AC, SA notes, and estimate

## Repo config

Add `.ado-mcp.json` to a repo to specify which ADO project it targets:

```json
{ "project": "YourProject", "team": "YourTeam" }
```
