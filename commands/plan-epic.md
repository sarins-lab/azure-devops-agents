---
description: Run the full BA → SA → Architect → PM planning pipeline for an epic. Creates all features, stories, and ADRs in Azure DevOps with full parent-child traceability.
argument-hint: <epic-id or epic-description>
allowed-tools: ["mcp__azure-devops__mcp_ado_wit_get_work_item", "mcp__azure-devops__mcp_ado_wit_get_work_items_batch_by_ids", "mcp__azure-devops__mcp_ado_wit_create_work_item", "mcp__azure-devops__mcp_ado_wit_update_work_item", "mcp__azure-devops__mcp_ado_wit_add_child_work_items", "mcp__azure-devops__mcp_ado_wit_list_backlog_work_items", "mcp__azure-devops__mcp_ado_wit_get_work_items_for_iteration", "mcp__azure-devops__mcp_ado_work_list_team_iterations", "mcp__azure-devops__mcp_ado_work_get_team_capacity", "mcp__azure-devops__mcp_ado_wiki_list_wikis", "mcp__azure-devops__mcp_ado_wiki_get_page", "mcp__azure-devops__mcp_ado_wiki_create_or_update_page"]
---

Run the full BA → SA → Architect → PM planning pipeline for an epic, then create all features, user stories, tasks, and ADRs in Azure DevOps with complete parent-child traceability.

## Arguments

- `$ARGUMENTS` — an ADO epic ID (number) or a free-text epic description

## Steps

### 1 — Load the epic

If `$ARGUMENTS` is a number, call `mcp_ado_wit_get_work_item` to retrieve the epic title, description, and acceptance criteria. Use those as the input context for all agents.

If `$ARGUMENTS` is a description, ask: *"Should I create a new Epic work item in ADO for this, or are you planning against an existing epic?"*

---

### 2 — BA phase

Use the **ba-agent** to decompose the epic into features and user stories with Given/When/Then acceptance criteria.

Pass to the agent: epic title, description, and ADO ID (if available).

**Pause.** Present the full story breakdown. Ask: *"Does this capture the business intent? Confirm or edit before I proceed to architecture."*

---

### 3 — SA phase

Use the **sa-agent** to add a technical design to each feature and an implementation note to each story.

Pass to the agent: the epic context + the full BA output.

**Pause.** Present the annotated plan. Ask: *"Does the technical approach look right? Confirm to proceed."*

---

### 4 — Architect phase

Use the **architect-agent** to write ADRs, audit cross-cutting concerns, and flag risks.

Pass to the agent: epic context + BA output + SA output.

**Pause.** Present ADRs and any new cross-cutting stories. Ask: *"Any architectural concerns before sprint planning?"*

---

### 5 — PM phase

Use the **pm-agent** to estimate story points, order by dependency and value, and assign stories to sprints.

Pass to the agent: all prior outputs.

**Pause.** Present the sprint plan table. Ask: *"Confirm to create all items in Azure DevOps."*

---

### 6 — Create items in ADO

Create in strict order (parents before children):

1. **Features** — call `mcp_ado_wit_add_child_work_items` with the epic ID as parent and the feature details. This creates the feature and sets the parent link in one call.
2. **User Stories** — for each feature, call `mcp_ado_wit_add_child_work_items` with the feature ID as parent and fields:
   - `System.Title`
   - `Microsoft.VSTS.Common.AcceptanceCriteria`
   - `System.Description` (SA notes + Architect risks)
   - `Microsoft.VSTS.Scheduling.StoryPoints`
   - `System.IterationPath`
3. **Cross-cutting stories** — same pattern under the relevant feature.
4. **ADR wiki pages** — call `mcp_ado_wiki_list_wikis` to get the wiki ID, then call `mcp_ado_wiki_create_or_update_page` with `path: "/Architecture/ADRs/ADR-NNN-<slug>"` and the full Markdown content.

---

### 7 — Verify traceability

For every created work item call `mcp_ado_wit_get_work_item` and confirm the `relations` array contains a parent link. If any link is missing, call `mcp_ado_wit_add_child_work_items` on the parent with the orphaned item's ID to fix it.

---

### 8 — Summary

Print a completion table:

| Type | Title | ADO ID | Parent | Sprint | Points |
|------|-------|--------|--------|--------|--------|
| Feature | ... | #N | #epic | — | — |
| Story | ... | #N | #feature | Sprint N | N |

Construct the epic URL from the ADO organization and project configured in `.ado-mcp.json`: `https://dev.azure.com/<org>/<project>/_workitems/edit/<epic-id>`
