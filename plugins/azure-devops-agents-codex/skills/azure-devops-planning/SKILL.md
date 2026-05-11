---
name: azure-devops-planning
description: Use when planning Azure DevOps Epics, Features, User Stories, acceptance criteria, sprint estimates, or ADRs from Codex. Handles slash-style requests such as /plan-epic, /plan-feature, and /plan-story by following the shared Azure DevOps planning workflow.
version: 1.0.0
---

# Azure DevOps Planning

Use the installed `azure-devops` MCP server and the planning conventions from this plugin.

Recognize these routes:

- `/plan-epic <id or description>`
- `/plan-feature <id or description>`
- `/plan-story <description> [under feature <id>]`

Follow the canonical workflow order:

1. BA: draft stories and acceptance criteria.
2. SA: add implementation notes and technical design.
3. Architect: review ADRs and cross-cutting concerns.
4. PM: estimate, split oversized stories, and recommend sprint placement.

Use official Microsoft Azure DevOps MCP tool names with the `mcp_ado_*` prefix.

Create work items with `mcp_ado_wit_add_child_work_items`, then add fields such as Acceptance Criteria and Story Points with `mcp_ado_wit_update_work_item`.

Read ADR content with `mcp_ado_wiki_get_page_content` after retrieving page metadata with `mcp_ado_wiki_get_page`.

Never create Azure DevOps work items until the user confirms the plan.
