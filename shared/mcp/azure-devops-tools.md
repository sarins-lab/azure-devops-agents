# Azure DevOps MCP Tooling

Use Microsoft's official `@azure-devops/mcp` package through the `azure-devops` MCP server. Tool names use the `mcp_ado_*` naming pattern.

## Planning Model

RUP-style SDLC concepts are canonical. Azure DevOps process terms are adapter output only.

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

UX artifacts and technical documentation are normally stored as Figma links, Azure DevOps wiki pages, repository docs, or Markdown references on related work items. They are not backlog items by default.

## Development Readiness Gate

Before implementation, repository edits, deployment, or configuration work starts, verify traceability to an existing approved Azure DevOps work item or confirmed RUP planning artifact. If the requested work is not already represented in Azure DevOps, capture it as a new Stakeholder Request or Change Request and run the SDLC workflow before development.

User-facing work must include a confirmed UX artifact or an explicit UX-not-applicable decision before development starts.

## Architecture And Diagram Quality

Architecture must be a cohesive system model: system boundary, actors, components, runtime flows, deployment, data, security, operations, decisions, tradeoffs, and open questions. Do not persist technology choices as confirmed work unless they are user-confirmed, repo-confirmed, or captured as ADR candidates.

Technical documentation must not introduce new architecture decisions. Mermaid diagrams in Azure DevOps wiki pages must use `::: mermaid` blocks, `graph TD;` or `graph LR;` for flowcharts, simple node IDs, quoted ASCII labels, no HTML, no Markdown labels, no angle-bracket placeholders, no raw Unicode symbols, and no GitHub-style Mermaid code fences.

## Process Profile

Before planning or creating work items, derive the target Azure DevOps process profile from metadata:

1. Call `mcp_ado_wit_list_backlogs` with `project` and `team`.
2. Identify default work item types for `Microsoft.EpicCategory`, `Microsoft.FeatureCategory`, `Microsoft.RequirementCategory`, and `Microsoft.TaskCategory` when present.
3. Call `mcp_ado_wit_get_work_item_type` for each target type before updating fields.
4. Use only fields that exist on the target work item type.

Field selection rules:

- Estimate field: first available of `Microsoft.VSTS.Scheduling.StoryPoints`, `Microsoft.VSTS.Scheduling.Effort`, `Microsoft.VSTS.Scheduling.Size`; otherwise do not write an estimate field.
- Acceptance criteria field: `Microsoft.VSTS.Common.AcceptanceCriteria` only if present; otherwise keep criteria in Markdown description.
- Requirement classification field: `Microsoft.VSTS.CMMI.RequirementType` only if present; otherwise classify with Markdown and tags.
- Tags: write through `/fields/System.Tags` only with `mcp_ado_wit_update_work_item`.

## Work Item Creation

`mcp_ado_wit_add_child_work_items` creates child work items and parent links. It supports title, description, area path, iteration path, and Markdown/HTML format.

It does not set Acceptance Criteria, Story Points, Effort, Size, Requirement Type, Tags, or custom fields. Add those afterward with `mcp_ado_wit_update_work_item`.

Use `mcp_ado_wit_work_items_link` only to repair or add links after creation.

Read back every created item with `mcp_ado_wit_get_work_item`. Never leave a created item parentless.

## Backlog Lookup

Call `mcp_ado_wit_list_backlogs` first to get backlog IDs, then call `mcp_ado_wit_list_backlog_work_items` with `project`, `team`, and `backlogId`.

## Wiki Lookup

Use this sequence:

1. `mcp_ado_wiki_list_wikis`
2. `mcp_ado_wiki_list_pages`
3. `mcp_ado_wiki_get_page`
4. `mcp_ado_wiki_get_page_content`

`mcp_ado_wiki_get_page` returns metadata. `mcp_ado_wiki_get_page_content` returns page text.

## Wiki Creation

Use `mcp_ado_wiki_create_or_update_page` for confirmed technical documentation, diagrams, and ADR pages. Do not write documentation pages before the user confirms the Technical Writer phase.
