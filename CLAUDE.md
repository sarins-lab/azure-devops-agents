# azure-devops-agents — Claude Code context

This repo is a Claude Code plugin providing a BA → SA → Architect → PM multi-agent sprint planning pipeline for Azure DevOps.

## MCP

The `azure-devops` MCP server is registered at user level via `~/.ado-mcp/ado-mcp.ps1`. It reads `.ado-mcp.json` from the current repo root and automatically injects `ado_mcp_project` and `ado_mcp_team`. No manual project override is needed in tool calls.

If `.ado-mcp.json` is absent, no default project is set — the MCP will require a project parameter on each tool call.

## Agents

Four specialist agents are in `agents/`. Invoke them via the commands in `commands/` or use `/plan-epic`, `/plan-feature`, or `/plan-story`.

## ADO field conventions

| Type | Required fields |
|------|----------------|
| Feature | Title, Description (SA technical approach), Tags |
| User Story | Title, Acceptance Criteria (Given/When/Then), Description (SA notes + Architect risks), Story Points, Iteration Path |
| Task | Title, Description, Remaining Work (hours), Assigned To |

## Traceability

After creating any work item, verify the parent link by reading it back with `wit_work_item`. Fix missing links with `wit_work_item_link_write`.
