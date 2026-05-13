---
name: azure-devops-planning
description: Use when the user wants to plan, setup, build, design, define, implement, secure, expose, document, diagram, estimate, schedule, or break down a software, platform, infrastructure, DevOps, security, UX, or technical documentation initiative that should become RUP-style Azure DevOps artifacts.
---

# Azure DevOps RUP Planning

Use this skill when the user expresses planning intent for software, platform, infrastructure, DevOps, security, UX, or documentation work. The user does not need to mention Azure DevOps, RUP, or a route name.

Treat natural language intent as a planning trigger when it starts or implies work such as "I want to", "we need to", "we should", "let's", "setup", "build", "design", "create", "define", "implement", "secure", "expose", "integrate", "document", "diagram", "estimate", or "break down".

Examples that should trigger:

- "I want to setup a highly secure home lab exposed through Cloudflare Tunnel."
- "We need to build certificate rotation."
- "Design the UX for self-service password reset."
- "Document the architecture with UML diagrams."
- "Break this feature into tasks."

If the request is not already phrased in RUP terms, map it to the closest canonical concept before planning. Ask a clarifying question only when the target concept or scope is genuinely ambiguous.

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

Map to Azure DevOps process terms only after retrieving and validating the target process metadata with `mcp_ado_wit_list_backlogs` and `mcp_ado_wit_get_work_item_type`.

## Routes

Preferred:

- `/capture-request`
- `/define-requirements`
- `/design-ux`
- `/plan-requirement`
- `/document-solution`
- `/plan-delivery`
- `/plan-task`

## Workflow

Run the SDLC role sequence in order, but stop at the last phase the request needs. For each phase, produce only that phase's output and pause before continuing.

1. Stakeholder Analyst
2. Requirements Analyst
3. UX Designer, when user-facing behavior is in scope
4. Solution Architect, with cohesive architecture views and ADR candidates
5. Technical Writer, with traceable docs and Azure DevOps wiki-safe Mermaid diagrams
6. Delivery Planner
7. Implementation Lead, when tasks are needed

Pause after each phase. Never create Azure DevOps work items until the user confirms the final plan.

## Development Readiness Gate

If the user asks to build, implement, change, fix, configure, deploy, secure, expose, integrate, document, diagram, or otherwise produce project work, first verify that the request is traceable to an existing approved Azure DevOps work item or confirmed RUP planning artifact.

If the work is not already represented in Azure DevOps, do not start development. Trigger planning by capturing the request as a new Stakeholder Request or Change Request, then run the SDLC phases until ready. Development can start only after requirements, UX for user-facing work, architecture, technical documentation, delivery planning, and needed implementation tasks are confirmed.

## Architecture And Diagram Quality

Architecture is not a technology list. It must define the system boundary, actors, components, runtime flows, deployment, data, security, operations, decisions, tradeoffs, and open questions. Every technology choice must be confirmed or listed as an ADR candidate.

Technical documentation must not introduce architecture decisions. Mermaid diagrams for Azure DevOps wiki must use `::: mermaid` blocks, `graph TD;` or `graph LR;` for flowcharts, simple node IDs, quoted ASCII labels, no HTML, no Markdown labels, no angle-bracket placeholders, no raw Unicode symbols, and no GitHub-style Mermaid code fences.

## Tooling

Use the official `azure-devops` MCP server and `mcp_ado_*` tool names.

Before writing, call `mcp_ado_wit_list_backlogs` and `mcp_ado_wit_get_work_item_type` to build the process profile. Create with `mcp_ado_wit_add_child_work_items`, update only discovered fields with `mcp_ado_wit_update_work_item`, and verify links with `mcp_ado_wit_get_work_item`.
