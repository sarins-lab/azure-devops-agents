---
description: Run the full BA → SA → Architect → PM planning pipeline for an epic. Creates all features, stories, and ADRs in Azure DevOps with full parent-child traceability.
argument-hint: <epic-id or epic-description>
allowed-tools: ["mcp__plugin_azure-devops-agents-claude_azure-devops__*", "mcp__azure-devops__mcp_ado_wit_get_work_item", "mcp__azure-devops__mcp_ado_wit_update_work_item", "mcp__azure-devops__mcp_ado_wit_add_child_work_items", "mcp__azure-devops__mcp_ado_wit_work_items_link", "mcp__azure-devops__mcp_ado_wit_list_backlogs", "mcp__azure-devops__mcp_ado_wit_list_backlog_work_items", "mcp__azure-devops__mcp_ado_wit_get_work_items_for_iteration", "mcp__azure-devops__mcp_ado_wit_query_by_wiql", "mcp__azure-devops__mcp_ado_work_list_team_iterations", "mcp__azure-devops__mcp_ado_work_get_team_capacity", "mcp__azure-devops__mcp_ado_work_get_team_settings", "mcp__azure-devops__mcp_ado_repo_list_repos_by_project", "mcp__azure-devops__mcp_ado_repo_list_directory", "mcp__azure-devops__mcp_ado_repo_get_file_content", "mcp__azure-devops__mcp_ado_search_code", "mcp__azure-devops__mcp_ado_search_workitem", "mcp__azure-devops__mcp_ado_search_wiki", "mcp__azure-devops__mcp_ado_wiki_list_wikis", "mcp__azure-devops__mcp_ado_wiki_list_pages", "mcp__azure-devops__mcp_ado_wiki_get_page", "mcp__azure-devops__mcp_ado_wiki_get_page_content", "mcp__azure-devops__mcp_ado_wiki_create_or_update_page"]
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

1. **Features** — call `mcp_ado_wit_add_child_work_items` with `parentId: <epic-id>`, `project`, `workItemType: "Feature"`, and `items` containing `title`, `description` (SA technical approach), and `format: "Markdown"`. This creates the feature and sets the parent link in one call. If tags are needed, call `mcp_ado_wit_update_work_item` on the created feature ID with `/fields/System.Tags`.
2. **User Stories** — for each feature, call `mcp_ado_wit_add_child_work_items` with `parentId: <feature-id>`, `project`, `workItemType: "User Story"`, and `items` containing `title`, `description` (SA notes + Architect risks), `format: "Markdown"`, and `iterationPath`.
3. **Story enrichment** — for each created story, call `mcp_ado_wit_update_work_item` with `updates` for:
   - `/fields/Microsoft.VSTS.Common.AcceptanceCriteria`
   - `/fields/Microsoft.VSTS.Scheduling.StoryPoints`
4. **Cross-cutting stories** — same create-then-update pattern under the relevant feature.
5. **ADR wiki pages** — call `mcp_ado_wiki_list_wikis` to get the wiki ID, optionally `mcp_ado_wiki_list_pages` to avoid number collisions, then call `mcp_ado_wiki_create_or_update_page` with `path: "/Architecture/ADRs/ADR-NNN-<slug>"` and the full Markdown content.

---

### 7 — Verify traceability

For every created work item call `mcp_ado_wit_get_work_item` and confirm the `relations` array contains a parent link. If any link is missing, call `mcp_ado_wit_work_items_link` with `project` and `updates: [{ "id": <child-id>, "linkToId": <parent-id>, "type": "parent" }]`.

---

### 8 — Summary

Print a completion table:

| Type | Title | ADO ID | Parent | Sprint | Points |
|------|-------|--------|--------|--------|--------|
| Feature | ... | #N | #epic | — | — |
| Story | ... | #N | #feature | Sprint N | N |

Construct the epic URL from the ADO organization and project configured in `.ado-mcp.json`: `https://dev.azure.com/<org>/<project>/_workitems/edit/<epic-id>`
