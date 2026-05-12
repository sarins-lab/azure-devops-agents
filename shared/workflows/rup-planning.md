# RUP Planning Workflow

Use RUP-style SDLC language as the planning model. Azure DevOps process names are persistence details only.

## Canonical Concepts

| RUP concept                | Meaning                                                                                              |
| -------------------------- | ---------------------------------------------------------------------------------------------------- |
| Stakeholder Request        | A business or stakeholder need, problem statement, opportunity, or change request.                   |
| Functional Requirement     | Observable behavior the solution must provide.                                                       |
| Non-Functional Requirement | Measurable quality, constraint, compliance, security, performance, reliability, or operability need. |
| UX Artifact                | User journey, screen flow, wireframe, Figma screen, prototype note, or UX acceptance criterion.      |
| Technical Requirement      | Engineering requirement or design constraint derived from functional or non-functional needs.        |
| Architecture               | A coherent set of boundaries, views, decisions, flows, deployment choices, data ownership, security controls, and operational constraints that satisfy confirmed requirements. |
| Technical Documentation    | System documentation, API notes, UML or technical diagrams, runbooks, and wiki-ready references.     |
| Delivery Slice             | A buildable, testable slice of work that realizes one or more requirements.                          |
| Task                       | Implementation work owned by an engineer or role.                                                    |

Never use Azure DevOps process terms such as User Story, Product Backlog Item, Requirement, or Issue as the planning model. Use them only when mapping to the target project process.

UX artifacts and technical documentation are not backlog items by default. Persist them as Figma links, Azure DevOps wiki pages, attachments, or Markdown references unless the user explicitly wants work items to track that work.

## SDLC Roles

Run these roles in order, pausing for user confirmation after each phase:

1. Stakeholder Analyst: capture the stakeholder request, business outcome, scope boundary, affected users, and success measures.
2. Requirements Analyst: derive functional and non-functional requirements with Given/When/Then or measurable acceptance criteria.
3. UX Designer: derive user journeys, screen flows, Figma-ready screen specifications, accessibility notes, and UX acceptance criteria for user-facing requirements.
4. Solution Architect: define cohesive architecture views, boundaries, runtime flows, deployment, data, security, operations, technical requirements, ADR candidates, and risks.
5. Technical Writer: produce traceable technical documentation and Azure DevOps wiki-safe Mermaid diagrams from the confirmed architecture package.
6. Delivery Planner: turn requirements and confirmed artifacts into delivery slices, estimate effort, order by dependency and value, and recommend iterations from team capacity.
7. Implementation Lead: break confirmed delivery slices into implementation tasks when requested or when the process requires child tasks.

The UX Designer phase can be marked not applicable for non-UI work, but the decision must be explicit. The Solution Architect phase must define architecture as a cohesive system model, not as a list of technologies. The Technical Writer phase can be lightweight for small changes, but any architecture, integration, API, data, or operational change should produce at least a documentation note or diagram decision.

## Architecture Definition Standard

Architecture is the coherent explanation of how confirmed requirements will be satisfied. It must include enough views for the team to understand the system before delivery planning starts.

The Solution Architect must produce these views when applicable:

1. Context view: actors, external systems, dependencies, trust levels, and system boundary.
2. Container and component view: major runtime units, responsibilities, interfaces, and ownership.
3. Runtime flow view: important request, identity, data, failure, and recovery flows.
4. Deployment and operations view: where things run, how they scale, how they are observed, and how they recover.
5. Security and trust view: trust boundaries, identities, secrets, certificates, authorization, network exposure, audit, and verification controls.
6. Data and integration view: data stores, ownership, retention, synchronization, and external contracts.
7. Decision view: confirmed decisions, proposed decisions, rejected alternatives, and ADR candidates.

Architecture must distinguish:

- Facts already provided by the user or discovered from repos/wiki.
- Assumptions that need confirmation.
- Proposed decisions that need ADRs.
- Confirmed decisions.
- Rejected alternatives.

Do not convert an assumption into a work item or wiki page as if it were confirmed. If a technology choice is not confirmed, it belongs in ADR candidates or open questions.

Before the Technical Writer phase, run an architecture cohesion check:

- Every technology choice is confirmed or listed as an ADR candidate.
- Every architecture element maps to at least one FR, NFR, UX artifact, or stakeholder constraint.
- Context, component, runtime, deployment, security, data, and operations views do not contradict each other.
- Open decisions are explicit and have owners or follow-up actions.
- Architecture is understandable without reading every work item individually.

## Mermaid Rendering Standard

Use Mermaid only when the diagram can render reliably in Azure DevOps wiki. Use this strict subset:

1. Use Azure DevOps wiki Mermaid blocks, not GitHub-style code fences.
2. Prefer `graph TD;`, `graph LR;`, or `sequenceDiagram`. Do not use the Mermaid `flowchart` keyword for Azure DevOps wiki pages.
3. Use simple node IDs: letters, numbers, and underscores only; start with a letter.
4. Put labels in square brackets with quoted ASCII text: `NodeA["Cloudflare Edge"]`.
5. Avoid HTML, Markdown, angle-bracket placeholders, emoji, Unicode symbols, slashes in node IDs, and raw line breaks inside labels.
6. Avoid `&`, `<`, `>`, `>=`, `<=`, pipes, and parentheses in labels when possible. Use words such as `and`, `at least`, or `less than`.
7. Use simple edge labels: `A -->|"HTTPS"| B`.
8. Keep subgraph names simple and do not link directly to or from a subgraph.
9. Never use unescaped placeholder values such as `<domain>` inside diagrams. Use example names in diagrams and describe placeholders outside the diagram.
10. Fence every Azure DevOps wiki diagram exactly with `::: mermaid` and `:::`.

````
::: mermaid
graph TD;
    Actor["Actor"] --> System["System"]
:::
````

11. Before publishing, scan each diagram for invalid node IDs, unbalanced brackets, unsupported Unicode, unsupported `flowchart` usage, GitHub-style Mermaid code fences, and placeholder tokens.

## Development Readiness Gate

Development must not start until the work is traceable to a confirmed Azure DevOps work item or a confirmed RUP planning artifact.

When the user asks to build, implement, change, fix, configure, deploy, secure, expose, integrate, document, diagram, or otherwise produce project work:

1. Check whether the request includes an Azure DevOps work item ID, URL, or explicit parent context.
2. If no ID or URL is provided, search Azure DevOps for a matching active work item when the MCP context is available. Prefer `mcp_ado_search_workitem`; use `mcp_ado_wit_query_by_wiql` when a structured state/type query is needed.
3. If no matching work item exists, or if the match is ambiguous, do not start development. Trigger the SDLC workflow by capturing the request as a new Stakeholder Request or Change Request.
4. Run the role sequence until the work is ready:
   - Stakeholder Analyst confirmed.
   - Requirements Analyst confirmed.
   - UX Designer confirmed for user-facing work, or explicitly marked not applicable for non-UI work.
   - Solution Architect confirmed for technical design, constraints, integrations, risks, and ADR candidates.
   - Technical Writer confirmed for required technical documentation, diagrams, API/interface notes, runbooks, and ADR pages.
   - Delivery Planner confirmed with delivery slices, estimates, dependencies, and iteration recommendation when capacity data is available.
   - Implementation Lead confirmed when implementation tasks are needed or the target process requires tasks.
5. Only after the readiness gate is satisfied may implementation, repository edits, or deployment work begin.

If the user asks for a direct code change and the readiness gate is not satisfied, respond with the planning route being started and begin the Stakeholder Analyst phase. Do not bypass this gate unless the user explicitly identifies an existing approved work item and asks only for implementation of that scoped item.

## Azure DevOps Process Mapping

Before creating or updating work items, build a runtime process profile:

1. Call `mcp_ado_wit_list_backlogs` with `project` and `team`.
2. Identify available backlog categories and default work item types:
   - `Microsoft.EpicCategory` for initiative-level containers.
   - `Microsoft.FeatureCategory` for capability-level containers, when present.
   - `Microsoft.RequirementCategory` for requirement or delivery-slice backlog items.
   - `Microsoft.TaskCategory` for implementation tasks.
3. Call `mcp_ado_wit_get_work_item_type` for each discovered target type before writing fields.
4. Select fields from actual metadata only:
   - Estimate: first available of `Microsoft.VSTS.Scheduling.StoryPoints`, `Microsoft.VSTS.Scheduling.Effort`, `Microsoft.VSTS.Scheduling.Size`, or none.
   - Acceptance criteria: `Microsoft.VSTS.Common.AcceptanceCriteria` only if present; otherwise keep criteria in Markdown description.
   - Requirement classification: `Microsoft.VSTS.CMMI.RequirementType` only if present; otherwise use tags such as `Functional`, `Non-Functional`, or `Technical`.
   - Tags: `System.Tags` only through `mcp_ado_wit_update_work_item`.
5. Use `mcp_ado_wit_add_child_work_items` only for title, description, area path, iteration path, format, and parent link.
6. Use `mcp_ado_wit_update_work_item` after creation for every additional field discovered in the profile.
7. Read back every created item with `mcp_ado_wit_get_work_item`; repair missing parent links with `mcp_ado_wit_work_items_link`.

Common work item mappings are hints only:

| RUP concept                | CMMI                                                                       | Scrum                                    | Agile                                           | Basic         |
| -------------------------- | -------------------------------------------------------------------------- | ---------------------------------------- | ----------------------------------------------- | ------------- |
| Stakeholder Request        | Change Request, or Requirement tagged `Stakeholder Request`                | Epic or PBI tagged `Stakeholder Request` | Epic or User Story tagged `Stakeholder Request` | Issue         |
| Functional Requirement     | Requirement, `Requirement Type=Functional` when available                  | Product Backlog Item                     | User Story                                      | Issue         |
| Non-Functional Requirement | Requirement, `Requirement Type=Quality of Service` or tag `Non-Functional` | PBI or Task tagged `Non-Functional`      | User Story or Task tagged `Non-Functional`      | Issue or Task |
| Technical Requirement      | Requirement or Task tagged `Technical`                                     | PBI or Task tagged `Technical`           | User Story or Task tagged `Technical`           | Task          |
| Delivery Slice             | Requirement                                                                | Product Backlog Item                     | User Story                                      | Issue         |
| Task                       | Task                                                                       | Task                                     | Task                                            | Task          |

Artifact persistence is separate from work item type mapping:

| Artifact                  | Preferred persistence                                                               |
| ------------------------- | ----------------------------------------------------------------------------------- |
| UX Artifact               | Figma file or prototype link, design spec wiki page, or Markdown link on work items |
| Technical Documentation   | Azure DevOps wiki page or repository documentation                                  |
| UML or Technical Diagram  | Azure DevOps wiki-safe Mermaid source in wiki/repo documentation, or a text table when Mermaid is not expressive enough |
| Architecture Decision     | Azure DevOps wiki ADR page under `/Architecture/ADRs/`                              |

## Workflow

### 1. Load Context

Read the resolved project and team from the launcher context. User-level defaults come from `~/.ado-mcp/config.json`; repo-level `.ado-mcp.json` overrides them when present. If a parent work item ID is provided, call `mcp_ado_wit_get_work_item` before planning. If no parent is provided and creation would produce an unlinked item, ask for the parent ID before writing anything.

For existing architecture context, use this wiki sequence:

1. `mcp_ado_wiki_list_wikis`
2. `mcp_ado_wiki_list_pages`
3. `mcp_ado_wiki_get_page`
4. `mcp_ado_wiki_get_page_content`

### 2. Stakeholder Analyst Phase

Produce:

- Stakeholder request statement.
- Business outcome and value.
- In-scope and out-of-scope boundaries.
- Stakeholders and affected users.
- Success measures.

Pause for confirmation.

### 3. Requirements Analyst Phase

Derive:

- Functional requirements with observable acceptance criteria.
- Non-functional requirements with measurable targets.
- Requirement dependencies and conflicts.
- Open questions.

Functional requirements should use user-observable language. Non-functional requirements must include a numeric or testable target wherever possible.

Pause for confirmation.

### 4. UX Designer Phase

For user-facing requirements, produce:

- Personas or affected user roles.
- User journeys and screen flows.
- Figma-ready screen specifications.
- Interaction states: loading, empty, error, success, disabled, validation, and permission states.
- Accessibility notes and UX acceptance criteria.

If the change has no user-facing behavior, state that UX is not applicable and why.

Create or update Figma artifacts only when a Figma tool or connector is available and the user confirms the UX phase. Otherwise return Figma-ready specifications and preserve any supplied Figma links in later work item descriptions or wiki pages.

Pause for confirmation.

### 5. Solution Architect Phase

Derive:

- Architecture definition: goal, system boundary, status, assumptions, and open decisions.
- Context, container/component, runtime flow, deployment/operations, security/trust, and data/integration views.
- Technical requirements and design constraints traceable to FR/NFR/UX inputs.
- Impacted services, repositories, components, data models, identities, secrets, certificates, and integrations.
- ADR candidates with options, recommended choice, tradeoffs, and rejected alternatives.
- Cross-cutting concerns, risks, mitigations, and failure modes.

Ground the design with `mcp_ado_repo_list_repos_by_project`, `mcp_ado_search_code`, `mcp_ado_repo_list_directory`, and `mcp_ado_repo_get_file_content` when repository context is needed.

Run the architecture cohesion check before asking for confirmation. Do not proceed to Technical Writer if the architecture is only a list of tools or disconnected diagrams.

Pause for confirmation.

### 6. Technical Writer Phase

Produce:

- Technical documentation plan.
- Wiki-ready technical documentation based only on the confirmed architecture package.
- Azure DevOps wiki-safe Mermaid diagrams for context, sequence, component, deployment, data-flow, security, or operational views when useful.
- API/interface documentation and runbook notes when relevant.
- Documentation traceability matrix tying docs and diagrams to requirements, technical requirements, ADRs, and work items.
- Documentation gaps and validation questions.

Use the Mermaid Rendering Standard above. If a diagram cannot be expressed safely in Mermaid, provide a text table and mark the richer diagram format as a documentation gap.

Create or update Azure DevOps wiki pages only after the user confirms the documentation phase.

Pause for confirmation.

### 7. Delivery Planner Phase

Produce:

- Delivery slices mapped back to the requirements and artifacts they satisfy.
- Fibonacci estimate per delivery slice using the profile's estimate field label when one exists.
- Sprint or iteration recommendation using `mcp_ado_work_get_team_settings`, `mcp_ado_work_list_team_iterations`, and `mcp_ado_work_get_team_capacity`.
- Split candidates and dependency order.
- Task breakdown when requested or needed.

If capacity is unavailable, do not assign work to iterations. State the missing capacity data and keep iteration placement as recommended only.

Pause before creating anything in Azure DevOps.

### 8. Persist To Azure DevOps

After explicit confirmation:

1. Create parent items before child items.
2. Use the runtime process profile to choose the Azure DevOps work item type for each RUP work concept.
3. Use Markdown descriptions to preserve the RUP artifact content: stakeholder request, requirement type, acceptance criteria, NFR targets, UX notes, technical notes, documentation links, ADR references, and traceability.
4. Update only fields proven to exist on the target work item type.
5. Create confirmed wiki pages for technical documentation and ADRs with `mcp_ado_wiki_create_or_update_page`.
6. Link or reference Figma artifacts when available; do not fabricate Figma URLs.
7. Verify every created item and parent link.

### 9. Return Summary

Return a compact table with:

| RUP concept | ADO type | Title | ADO ID | Parent | Iteration | Estimate | Artifact links |
| ----------- | -------- | ----- | ------ | ------ | --------- | -------- | -------------- |

Also list any fields skipped because the target process did not expose them, and any UX or documentation artifacts that still need external creation or validation.

Use the preferred RUP route names in client instructions. Do not add separate legacy command or prompt files.
