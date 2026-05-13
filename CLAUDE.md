# azure-devops-agents - Claude Code context

This plugin provides a RUP-style SDLC planning workflow for Azure DevOps.

## Principle

Plan in RUP language. Persist in Azure DevOps process language only after discovering the project process.

Canonical concepts:

- Stakeholder Request
- Functional Requirement
- Non-Functional Requirement
- UX Artifact
- Technical Requirement
- Architecture
- Technical Documentation
- Delivery Slice
- Task

## SDLC Roles

Run these phases in order and pause after each phase:

1. Stakeholder Analyst: request, scope, value, affected users, success measures.
2. Requirements Analyst: functional and non-functional requirements with acceptance criteria.
3. UX Designer: user journeys, screen flows, Figma-ready screen specifications, accessibility notes, UX acceptance criteria.
4. Solution Architect: cohesive architecture views, boundaries, runtime flows, deployment, data, security, operations, technical requirements, ADR candidates.
5. Technical Writer: traceable technical documentation and Azure DevOps wiki-safe Mermaid diagrams from confirmed architecture.
6. Delivery Planner: estimates, dependencies, splits, and iteration recommendation.
7. Implementation Lead: task breakdown when requested or required.

Do not create Azure DevOps work items until the user confirms the final plan.

## Development Readiness Gate

Before starting implementation, repository edits, deployment, or configuration work, verify that the request is traceable to an existing approved Azure DevOps work item or a confirmed RUP planning artifact. If the work is not already in Azure DevOps, trigger planning first by capturing it as a new Stakeholder Request or Change Request.

Only start development after the required SDLC phases are confirmed, including UX Designer for user-facing work or an explicit UX-not-applicable decision for non-UI work.

## Architecture And Diagrams

Architecture is the cohesive model of boundaries, components, runtime flows, deployment, data, security, operations, and decisions. Do not treat a technology list as architecture. Every technology choice must be confirmed or listed as an ADR candidate.

Technical documentation must preserve the confirmed architecture and use Azure DevOps wiki-safe Mermaid: `::: mermaid` blocks, `graph TD;` or `graph LR;` for flowcharts, simple node IDs, quoted ASCII labels, no HTML, no Markdown labels, no angle-bracket placeholders, and no GitHub-style Mermaid code fences.

## Routes

Run the planning workflow automatically when the user expresses planning intent, even without Azure DevOps, RUP, or route-name wording. Trigger on phrases such as "I want to", "we need to", "we should", "let's", "setup", "build", "design", "create", "define", "implement", "secure", "expose", "integrate", "document", "diagram", "estimate", and "break down".

Example: "I want to setup a highly secure home lab exposed through Cloudflare Tunnel" maps to `/capture-request`.

Preferred text routes:

- `/capture-request`
- `/define-requirements`
- `/design-ux`
- `/plan-requirement`
- `/document-solution`
- `/plan-delivery`
- `/plan-task`

## Azure DevOps Mapping

Use `mcp_ado_wit_list_backlogs` and `mcp_ado_wit_get_work_item_type` to build the runtime process profile before writing anything. CMMI, Scrum, Agile, and Basic are target process mappings, not planning vocabulary.

Create parent-before-child with `mcp_ado_wit_add_child_work_items`, update only discovered fields with `mcp_ado_wit_update_work_item`, and verify every link with `mcp_ado_wit_get_work_item`.
