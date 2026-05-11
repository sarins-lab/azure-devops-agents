# azure-devops-agents — Codex context

This repo is a multi-agent sprint planning plugin for Azure DevOps, designed for Claude Code, VS Code, and Codex.

## MCP server

The `azure-devops` MCP server is configured in `~/.codex/config.toml` and backed by `~/.ado-mcp/ado-mcp.ps1`. The launcher reads `.ado-mcp.json` from the repo root and automatically sets the ADO project. No manual project override is needed.

Run `.\scripts\install.ps1 -Organization <your-org>` once to configure the MCP for all tools.

## Package layout

Canonical planning workflows live in `shared/workflows/` and MCP tool rules live in `shared/mcp/`. Client packages live in `plugins/azure-devops-agents-claude/`, `plugins/azure-devops-agents-vscode/`, and `plugins/azure-devops-agents-codex/`.

## Agents

| Agent     | File                        | Role                                                    |
| --------- | --------------------------- | ------------------------------------------------------- |
| BA        | `agents/ba-agent.md`        | User stories with Given/When/Then acceptance criteria   |
| SA        | `agents/sa-agent.md`        | Technical design, dependency order, risk register       |
| Architect | `agents/architect-agent.md` | ADRs, cross-cutting concern audit, principle violations |
| PM        | `agents/pm-agent.md`        | Fibonacci estimates, story splitting, sprint assignment |

## Commands

- `plan-epic` — Full BA → SA → Architect → PM pipeline for an epic
- `plan-feature` — Same pipeline scoped to one feature
- `plan-story` — Single user story with AC, SA notes, and estimate

In Codex and VS Code, treat `/plan-epic ...`, `/plan-feature ...`, and `/plan-story ...` as explicit planning instructions even though those clients do not load Claude command files. Run the matching workflow directly as a single model, using the canonical rules in `shared/workflows/`.

## ADO field conventions

| Type       | Required fields                                                                                                                             |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Feature    | Title, Description (SA technical approach), Tags (feature area)                                                                             |
| User Story | Title, Acceptance Criteria (BA — Given/When/Then), Description (SA implementation notes + Architect concerns), Story Points, Iteration Path |
| Task       | Title, Description, Remaining Work (hours), Assigned To                                                                                     |

## Traceability

After creating any work item, verify the parent link by reading it back with `mcp_ado_wit_get_work_item`. Fix missing links with `mcp_ado_wit_work_items_link`. Never leave an item parentless.

## ADO create pattern

Use `mcp_ado_wit_add_child_work_items` only for title, description, area path, iteration path, and parent link. Add Acceptance Criteria, Story Points, Tags, and other fields afterward with `mcp_ado_wit_update_work_item`.

## Repo config

Add `.ado-mcp.json` to a repo to specify which ADO project it targets:

```json
{ "project": "YourProject", "team": "YourTeam" }
```
