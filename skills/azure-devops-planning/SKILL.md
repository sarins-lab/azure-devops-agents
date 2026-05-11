---
name: azure-devops-planning
description: Use when planning Azure DevOps Epics, Features, User Stories, acceptance criteria, estimates, sprint placement, or ADRs through the Azure DevOps MCP server.
---

# Azure DevOps Planning

Use this skill when the user expresses planning intent for Azure DevOps work.

## MCP Server

Use the `azure-devops` MCP server backed by Microsoft's official `@azure-devops/mcp` package.
Tool names use the `mcp_ado_*` naming pattern.

The MCP launcher reads `.ado-mcp.json` from the repository root and injects the Azure DevOps project and team at runtime:

```json
{ "project": "YourProject", "team": "YourTeam" }
```

## Planning Routes

Use these routes for planning requests:

| Signal | Route | Agents |
|--------|-------|--------|
| Broad initiative, multiple features, or Epic | `/plan-epic` | ba-agent -> sa-agent -> architect-agent -> pm-agent |
| Specific capability or Feature | `/plan-feature` | ba-agent -> sa-agent -> architect-agent -> pm-agent |
| Single behavior or User Story | `/plan-story` | ba-agent -> sa-agent -> pm-agent |
| Ambiguous scope | Ask first | "Are we planning an Epic, a Feature, or a User Story?" |

Trigger phrases include "we need to", "we should", "let's", "I want to", "plan", "design", "build", "create", "define", and "implement".

Do not trigger the planning pipeline for lookup-only questions such as "what is in sprint 3?" or "show me story #42".

Pause for user confirmation after each agent phase before proceeding.

## Tooling Rules

Create child work items with `mcp_ado_wit_add_child_work_items`.
Use it only for title, description, area path, iteration path, format, and parent link.

Add fields such as Acceptance Criteria, Story Points, and Tags afterward with `mcp_ado_wit_update_work_item`.

After creating any work item, read it back with `mcp_ado_wit_get_work_item`.
If the parent link is missing, repair it with `mcp_ado_wit_work_items_link`.

Read ADR content with this wiki sequence:

1. `mcp_ado_wiki_list_wikis`
2. `mcp_ado_wiki_list_pages`
3. `mcp_ado_wiki_get_page`
4. `mcp_ado_wiki_get_page_content`

`mcp_ado_wiki_get_page` returns metadata. `mcp_ado_wiki_get_page_content` returns the page text.
