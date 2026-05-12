---
name: azure-devops-planning
description: Use when the user wants to plan, setup, build, design, define, implement, secure, expose, document, diagram, estimate, schedule, or break down a software, platform, infrastructure, DevOps, security, UX, or technical documentation initiative into RUP-style Azure DevOps artifacts from Codex.
version: 1.0.0
---

# Azure DevOps RUP Planning

Use the installed `azure-devops` MCP server and the RUP planning conventions from this plugin.

Trigger on natural planning intent even when the user does not mention Azure DevOps, RUP, or a route name. Phrases such as "I want to", "we need to", "we should", "let's", "setup", "build", "design", "create", "define", "implement", "secure", "expose", "integrate", "document", "diagram", "estimate", or "break down" should start the workflow unless the user is only asking for a lookup.

For example, "I want to setup a highly secure home lab exposed through Cloudflare Tunnel" is a Stakeholder Request and should start the Stakeholder Analyst phase.

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

Preferred routes are `/capture-request`, `/define-requirements`, `/design-ux`, `/plan-requirement`, `/document-solution`, `/plan-delivery`, and `/plan-task`.

Run the SDLC role sequence in order, stopping at the last phase the request needs:

1. Stakeholder Analyst
2. Requirements Analyst
3. UX Designer, when user-facing behavior is in scope
4. Solution Architect, with cohesive architecture views and ADR candidates
5. Technical Writer, with traceable docs and Azure DevOps wiki-safe Mermaid diagrams
6. Delivery Planner
7. Implementation Lead, when tasks are needed

Before development starts, verify that the request is traceable to an existing approved Azure DevOps work item or confirmed RUP planning artifact. If the work is not already represented in Azure DevOps, do not start implementation; capture it as a new Stakeholder Request or Change Request and run the SDLC workflow first. User-facing work must have UX completed or explicitly marked not applicable.

Architecture must be a cohesive system model, not a list of tools. Every technology choice must be confirmed or listed as an ADR candidate. Technical documentation must not introduce architecture decisions. Mermaid diagrams for Azure DevOps wiki must use `::: mermaid` blocks, `graph TD;` or `graph LR;` for flowcharts, simple node IDs, quoted ASCII labels, no HTML, no Markdown labels, no angle-bracket placeholders, no raw Unicode symbols, and no GitHub-style Mermaid code fences.

Before writing to Azure DevOps, build the runtime process profile with `mcp_ado_wit_list_backlogs` and `mcp_ado_wit_get_work_item_type`. Then map RUP artifacts to the active process, create parent-before-child, update only discovered fields, and verify traceability.
