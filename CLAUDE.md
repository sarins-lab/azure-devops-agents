# azure-devops-agents — Claude Code context

This repo is a Claude Code plugin providing a BA → SA → Architect → PM multi-agent sprint planning pipeline for Azure DevOps. The four agents and three commands are loaded and available in this session.

## MCP

The `azure-devops` MCP server is registered at user level via `~/.ado-mcp/ado-mcp.ps1`. It reads `.ado-mcp.json` from the repo root and automatically injects `ado_mcp_project` and `ado_mcp_team`.

## Package layout

Canonical planning workflows live in `shared/workflows/`; official Azure DevOps MCP tool rules live in `shared/mcp/`; client packages live in `plugins/azure-devops-agents-claude/`, `plugins/azure-devops-agents-vscode/`, and `plugins/azure-devops-agents-codex/`.

## Automatic planning pipeline

Run the planning pipeline automatically when the user expresses planning intent — do not wait for an explicit command. Use the specialist agents for each phase:

| Signal | Level | Agents to invoke |
|--------|-------|-----------------|
| Epic, broad initiative, multiple features | Epic | ba-agent → sa-agent → architect-agent → pm-agent |
| Feature, specific capability | Feature | ba-agent → sa-agent → architect-agent → pm-agent |
| User story, "as a user", single behaviour | Story | ba-agent → sa-agent → pm-agent |
| Ambiguous | Ask | "Are we planning an Epic, a Feature, or a User Story?" |

**Trigger phrases:** "we need to", "we should", "let's", "I want to", "plan", "design", "build", "create", "define", "implement"

**Do not trigger** for queries about existing work ("what's in sprint 3?", "show me story #42").

Pause for user confirmation after each agent phase before proceeding to the next.

## ADO field conventions

| Type | Required fields |
|------|----------------|
| Feature | Title, Description (SA technical approach), Tags |
| User Story | Title, Acceptance Criteria (Given/When/Then), Description (SA notes + Architect risks), Story Points, Iteration Path |
| Task | Title, Description, Remaining Work (hours), Assigned To |

## Traceability

After creating any work item, verify the parent link with `mcp_ado_wit_get_work_item`. Fix missing links with `mcp_ado_wit_work_items_link`. Never leave a work item parentless.

## ADO create pattern

Use `mcp_ado_wit_add_child_work_items` only for title, description, area path, iteration path, and parent link. Add Acceptance Criteria, Story Points, Tags, and other fields afterward with `mcp_ado_wit_update_work_item`.
