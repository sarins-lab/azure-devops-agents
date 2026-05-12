# azure-devops-agents - Codex context

This repo packages a RUP-style Azure DevOps planning assistant for Codex, Claude Code, and VS Code Copilot.

## Principle

Use RUP-style SDLC language as the planning model. Azure DevOps process names are persistence details only.

Canonical planning concepts:

- Stakeholder Request
- Functional Requirement
- Non-Functional Requirement
- UX Artifact
- Technical Requirement
- Architecture
- Technical Documentation
- Delivery Slice
- Task

Map these concepts to Azure DevOps only after discovering the target project process from backlog and work item type metadata.

## MCP Server

The `azure-devops` MCP server is configured at user level. The installer captures a default Azure DevOps `project` and optional `team` in `~/.ado-mcp/config.json`. The launcher reads `.ado-mcp.json` from the repo root and uses its `project` and `team` to override those user defaults.

Use Microsoft's official `@azure-devops/mcp` server and `mcp_ado_*` tool names.

## SDLC Roles

| Role | Responsibility |
| --- | --- |
| Stakeholder Analyst | Capture stakeholder request, scope, value, affected users, and success measures. |
| Requirements Analyst | Derive functional and non-functional requirements with testable acceptance criteria. |
| UX Designer | Derive user journeys, screen flows, Figma-ready screen specifications, accessibility notes, and UX acceptance criteria. |
| Solution Architect | Define cohesive architecture views, boundaries, runtime flows, deployment, data, security, operations, technical requirements, and ADR candidates. |
| Technical Writer | Produce traceable technical documentation and Azure DevOps wiki-safe Mermaid diagrams from the confirmed architecture package. |
| Delivery Planner | Estimate, sequence, split work, and recommend iterations from capacity. |
| Implementation Lead | Break confirmed delivery slices into tasks when requested or required. |

Pause after each role phase for confirmation. Never create Azure DevOps work items until the user confirms the final plan.

## Development Readiness Gate

Before starting implementation, repository edits, deployment, or configuration work, verify that the request is traceable to an existing approved Azure DevOps work item or a confirmed RUP planning artifact. If the user asks for work that is not already represented in Azure DevOps, trigger the SDLC workflow first by capturing it as a new Stakeholder Request or Change Request.

Only start development after Stakeholder Analyst, Requirements Analyst, UX Designer when applicable, Solution Architect, Technical Writer, Delivery Planner, and needed Implementation Lead phases are confirmed. UX must be completed for user-facing work or explicitly marked not applicable for non-UI work.

## Architecture And Diagrams

Architecture must be a cohesive system model, not a list of tools. The Solution Architect must define context, component, runtime, deployment, security/trust, data/integration, operations, decisions, tradeoffs, and open questions. Every technology choice must be confirmed or marked as an ADR candidate.

Technical Writer output must not introduce new architecture decisions. Mermaid diagrams for Azure DevOps wiki must use `::: mermaid` blocks, `graph TD;` or `graph LR;` for flowcharts, simple node IDs, quoted ASCII labels, no HTML, no Markdown in labels, no angle-bracket placeholders, no raw Unicode symbols, and no GitHub-style Mermaid code fences.

## Routes

Preferred routes:

- `/capture-request <description>`
- `/define-requirements <request or parent-id>`
- `/design-ux <requirements or parent-id>`
- `/plan-requirement <description> [under <parent-id>]`
- `/document-solution <requirements or architecture>`
- `/plan-delivery <requirement or parent-id>`
- `/plan-task <delivery-slice or parent-id>`

Run the planning workflow automatically when the user expresses planning intent, even when they do not mention Azure DevOps, RUP, or a route name. Trigger phrases include "I want to", "we need to", "we should", "let's", "setup", "build", "design", "create", "define", "implement", "secure", "expose", "integrate", "document", "diagram", "estimate", and "break down".

Example: "I want to setup a highly secure home lab exposed through Cloudflare Tunnel" maps to `/capture-request` and starts with the Stakeholder Analyst phase.

Do not trigger for lookup-only questions such as "what is in sprint 3?" or "show work item 42".

## Process Mapping

Before writing to Azure DevOps:

1. Call `mcp_ado_wit_list_backlogs`.
2. Identify `Epic`, `Feature`, requirement-level, and task-level categories when present.
3. Call `mcp_ado_wit_get_work_item_type` for every target work item type.
4. Select estimate, acceptance criteria, classification, and tag fields from actual metadata only.
5. Create parent-before-child with `mcp_ado_wit_add_child_work_items`.
6. Add fields with `mcp_ado_wit_update_work_item`.
7. Read back with `mcp_ado_wit_get_work_item` and repair links with `mcp_ado_wit_work_items_link` if needed.

Common mappings are hints, not rules:

| RUP concept | CMMI | Scrum | Agile | Basic |
| --- | --- | --- | --- | --- |
| Stakeholder Request | Change Request or Requirement tagged `Stakeholder Request` | Epic or PBI | Epic or User Story | Issue |
| Functional Requirement | Requirement, `Requirement Type=Functional` when available | Product Backlog Item | User Story | Issue |
| Non-Functional Requirement | Requirement tagged `Non-Functional` or `Quality of Service` | PBI or Task | User Story or Task | Issue or Task |
| Technical Requirement | Requirement or Task tagged `Technical` | PBI or Task | User Story or Task | Task |
| Delivery Slice | Requirement | Product Backlog Item | User Story | Issue |
| Task | Task | Task | Task | Task |

UX artifacts and technical documentation are normally persisted as Figma links, Azure DevOps wiki pages, repository docs, or Markdown references on related work items, not as backlog items unless the user explicitly asks.

## Shared Files

Canonical workflow: `shared/workflows/rup-planning.md`.
Azure DevOps tooling contract: `shared/mcp/azure-devops-tools.md`.

Each client should have one primary instruction file. Do not add separate command or prompt files for old route names.
