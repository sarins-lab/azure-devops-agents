# Azure DevOps RUP Planning - VS Code Copilot Adapter

Use the `azure-devops` MCP server for Azure DevOps operations. The installer stores a default `project` and optional `team` in `~/.ado-mcp/config.json`; the launcher reads `.ado-mcp.json` from the repo root to override those values when present.

## Canonical Model

Plan in RUP-style SDLC language:

- Stakeholder Request
- Functional Requirement
- Non-Functional Requirement
- UX Artifact
- Technical Requirement
- Architecture
- Technical Documentation
- Delivery Slice
- Task

Azure DevOps process names are used only when persisting work items.

## Routes

Run the planning workflow automatically when the user expresses planning intent, even without Azure DevOps, RUP, or route-name wording. Trigger on phrases such as "I want to", "we need to", "we should", "let's", "setup", "build", "design", "create", "define", "implement", "secure", "expose", "integrate", "document", "diagram", "estimate", and "break down".

Example: "I want to setup a highly secure home lab exposed through Cloudflare Tunnel" maps to `/capture-request`.

Preferred routes:

- `/capture-request <description>`
- `/define-requirements <request or parent-id>`
- `/design-ux <requirements or parent-id>`
- `/plan-requirement <description> [under <parent-id>]`
- `/document-solution <requirements or architecture>`
- `/plan-delivery <requirement or parent-id>`
- `/plan-task <delivery-slice or parent-id>`

## Workflow

Run these phases and pause after each:

1. Stakeholder Analyst: capture request, value, scope, stakeholders, affected users, success measures.
2. Requirements Analyst: derive functional and non-functional requirements with acceptance criteria.
3. UX Designer: derive user journeys, screen flows, Figma-ready screen specifications, accessibility notes, UX acceptance criteria.
4. Solution Architect: define cohesive architecture views, boundaries, runtime flows, deployment, data, security, operations, technical requirements, ADR candidates.
5. Technical Writer: produce traceable technical documentation and Azure DevOps wiki-safe Mermaid diagrams from confirmed architecture.
6. Delivery Planner: derive delivery slices, estimate, order by dependency and value, recommend iterations from capacity.
7. Implementation Lead: break work into tasks when requested or required.

## Development Readiness Gate

Before starting implementation, repository edits, deployment, or configuration work, verify that the request is traceable to an existing approved Azure DevOps work item or a confirmed RUP planning artifact. If the user asks for work that is not already represented in Azure DevOps, trigger the SDLC workflow first by capturing it as a new Stakeholder Request or Change Request.

Only start development after Stakeholder Analyst, Requirements Analyst, UX Designer when applicable, Solution Architect, Technical Writer, Delivery Planner, and needed Implementation Lead phases are confirmed. UX must be completed for user-facing work or explicitly marked not applicable for non-UI work.

## Architecture And Diagrams

Architecture must be a cohesive system model, not a list of tools. Every technology choice must be confirmed or marked as an ADR candidate. Technical Writer output must not introduce new architecture decisions.

Mermaid diagrams for Azure DevOps wiki must use `::: mermaid` blocks, `graph TD;` or `graph LR;` for flowcharts, simple node IDs, quoted ASCII labels, no HTML, no Markdown in labels, no angle-bracket placeholders, no raw Unicode symbols, and no GitHub-style Mermaid code fences.

## Azure DevOps Mapping

Before writing, build a process profile using `mcp_ado_wit_list_backlogs` and `mcp_ado_wit_get_work_item_type`.

Create parent-before-child with `mcp_ado_wit_add_child_work_items`, update only fields discovered in metadata with `mcp_ado_wit_update_work_item`, and verify parent links with `mcp_ado_wit_get_work_item`.
