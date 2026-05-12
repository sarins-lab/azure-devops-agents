# Azure DevOps RUP Planning - Codex Adapter

The `azure-devops` MCP server is configured at user level via `~/.codex/config.toml`.
The installer stores a default `project` and optional `team` in `~/.ado-mcp/config.json`. Place `.ado-mcp.json` in any repo root to override `project` and `team`; the launcher injects the resolved values automatically.

## Canonical Model

Use RUP-style SDLC concepts:

- Stakeholder Request
- Functional Requirement
- Non-Functional Requirement
- UX Artifact
- Technical Requirement
- Architecture
- Technical Documentation
- Delivery Slice
- Task

Azure DevOps process terms are persistence targets only. Do not plan in User Story, Product Backlog Item, CMMI Requirement, or Issue language unless you are describing the final process mapping.

## Routing

Run the planning workflow automatically when planning intent is detected, even when the user does not mention Azure DevOps, RUP, or a route name. Trigger phrases include "I want to", "we need to", "we should", "let's", "setup", "build", "design", "create", "define", "implement", "secure", "expose", "integrate", "document", "diagram", "estimate", and "break down".

Example: "I want to setup a highly secure home lab exposed through Cloudflare Tunnel" maps to `/capture-request` and starts with the Stakeholder Analyst phase.

Recognize these preferred routes:

- `/capture-request <description>`
- `/define-requirements <request or parent-id>`
- `/design-ux <requirements or parent-id>`
- `/plan-requirement <description> [under <parent-id>]`
- `/document-solution <requirements or architecture>`
- `/plan-delivery <requirement or parent-id>`
- `/plan-task <delivery-slice or parent-id>`

Do not trigger for lookup-only queries such as "what is in sprint 3?" or "show work item 42".

## Role Workflow

1. Stakeholder Analyst: capture request, business outcome, scope boundaries, stakeholders, affected users, and success measures. Pause for confirmation.
2. Requirements Analyst: derive functional and non-functional requirements with testable acceptance criteria and explicit out-of-scope boundaries. Pause for confirmation.
3. UX Designer: derive user journeys, screen flows, Figma-ready screen specifications, accessibility notes, and UX acceptance criteria for user-facing requirements. Pause for confirmation.
4. Solution Architect: define cohesive architecture views, boundaries, runtime flows, deployment, data, security, operations, technical requirements, ADR candidates, and risks. Pause for confirmation.
5. Technical Writer: produce traceable technical documentation and Azure DevOps wiki-safe Mermaid diagrams from the confirmed architecture package. Pause for confirmation.
6. Delivery Planner: derive delivery slices, estimate, order by dependency/value, query iterations/capacity, and recommend sprint placement. Pause before creating anything.
7. Implementation Lead: create task breakdown only when requested or required by the workflow.

## Development Readiness Gate

Before starting implementation, repository edits, deployment, or configuration work, verify that the request is traceable to an existing approved Azure DevOps work item or a confirmed RUP planning artifact. If the user asks for work that is not already represented in Azure DevOps, trigger the SDLC workflow first by capturing it as a new Stakeholder Request or Change Request.

Only start development after Stakeholder Analyst, Requirements Analyst, UX Designer when applicable, Solution Architect, Technical Writer, Delivery Planner, and needed Implementation Lead phases are confirmed. UX must be completed for user-facing work or explicitly marked not applicable for non-UI work.

## Architecture And Diagrams

Architecture must be a cohesive system model, not a list of tools. The Solution Architect must define context, component, runtime, deployment, security/trust, data/integration, operations, decisions, tradeoffs, and open questions. Every technology choice must be confirmed or marked as an ADR candidate.

Technical Writer output must not introduce new architecture decisions. Mermaid diagrams for Azure DevOps wiki must use `::: mermaid` blocks, `graph TD;` or `graph LR;` for flowcharts, simple node IDs, quoted ASCII labels, no HTML, no Markdown in labels, no angle-bracket placeholders, no raw Unicode symbols, and no GitHub-style Mermaid code fences.

## Azure DevOps Persistence

Before creating or updating work items:

1. Call `mcp_ado_wit_list_backlogs` with `project` and `team`.
2. Identify default work item types for epic, feature, requirement-level, and task categories.
3. Call `mcp_ado_wit_get_work_item_type` for target types.
4. Select fields from metadata only: estimate, acceptance criteria, requirement classification, tags, iteration path.
5. Create parent-before-child with `mcp_ado_wit_add_child_work_items`.
6. Enrich fields afterward with `mcp_ado_wit_update_work_item`.
7. Verify with `mcp_ado_wit_get_work_item`; repair missing links with `mcp_ado_wit_work_items_link`.

If the process is CMMI, Functional Requirements usually map to `Requirement` with `Requirement Type=Functional` when the field exists. Scrum and Agile map the same RUP artifact to their own requirement-level backlog item. The metadata response is authoritative.
