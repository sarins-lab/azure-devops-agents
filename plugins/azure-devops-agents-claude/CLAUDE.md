# Azure DevOps RUP Planning - Claude Adapter

The `azure-devops` MCP server is declared by the Claude plugin through the repo root `.mcp.json`, not through a standalone user-level registration. The installer stores a default `project` and optional `team` in `~/.ado-mcp/config.json`. Place `.ado-mcp.json` in any repo root to override `project` and `team`; the launcher injects the resolved values automatically.

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

Azure DevOps process terms are persistence targets only.

## Planning Routes

Run the planning workflow automatically when the user expresses planning intent, even without Azure DevOps, RUP, or route-name wording. Trigger on phrases such as "I want to", "we need to", "we should", "let's", "setup", "build", "design", "create", "define", "implement", "secure", "expose", "integrate", "document", "diagram", "estimate", and "break down".

Example: "I want to setup a highly secure home lab exposed through Cloudflare Tunnel" maps to `/capture-request`.

Preferred routes:

- `/capture-request`
- `/define-requirements`
- `/design-ux`
- `/plan-requirement`
- `/document-solution`
- `/plan-delivery`
- `/plan-task`

## Role Workflow

Use the SDLC role sequence:

1. Stakeholder Analyst: request, value, scope, stakeholders, success measures.
2. Requirements Analyst: functional and non-functional requirements with acceptance criteria.
3. UX Designer: user journeys, screen flows, Figma-ready screen specifications, accessibility notes, UX acceptance criteria.
4. Solution Architect: cohesive architecture views, boundaries, runtime flows, deployment, data, security, operations, technical requirements, ADR candidates.
5. Technical Writer: traceable technical documentation and Azure DevOps wiki-safe Mermaid diagrams from confirmed architecture.
6. Delivery Planner: estimates, dependencies, split candidates, iteration recommendation.
7. Implementation Lead: tasks when requested or required.

Pause after each phase. Never create Azure DevOps work items until the user confirms the final plan.

## Development Readiness Gate

Before starting implementation, repository edits, deployment, or configuration work, verify that the request is traceable to an existing approved Azure DevOps work item or a confirmed RUP planning artifact. If the work is not already in Azure DevOps, trigger planning first by capturing it as a new Stakeholder Request or Change Request.

Only start development after the required SDLC phases are confirmed, including UX Designer for user-facing work or an explicit UX-not-applicable decision for non-UI work.

## Architecture And Diagrams

Architecture is the cohesive model of boundaries, components, runtime flows, deployment, data, security, operations, and decisions. Do not treat a technology list as architecture. Every technology choice must be confirmed or listed as an ADR candidate.

Technical documentation must preserve the confirmed architecture and use Azure DevOps wiki-safe Mermaid: `::: mermaid` blocks, `graph TD;` or `graph LR;` for flowcharts, simple node IDs, quoted ASCII labels, no HTML, no Markdown labels, no angle-bracket placeholders, and no GitHub-style Mermaid code fences.

## Azure DevOps Persistence

Build a process profile with `mcp_ado_wit_list_backlogs` and `mcp_ado_wit_get_work_item_type` before writing. Map RUP artifacts to the active process at creation time, then create parent-before-child with `mcp_ado_wit_add_child_work_items`, update fields with `mcp_ado_wit_update_work_item`, and verify links with `mcp_ado_wit_get_work_item`.
