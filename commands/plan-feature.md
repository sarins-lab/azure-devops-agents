---
description: Run the BA → SA → Architect → PM pipeline for a single feature. Decomposes it into stories, adds technical design and ADRs, estimates, and creates everything in Azure DevOps.
argument-hint: <feature-id or feature-description> [under epic <epic-id>]
allowed-tools: ["mcp__plugin_azure-devops-agents-claude_azure-devops__*", "mcp__azure-devops__mcp_ado_wit_get_work_item", "mcp__azure-devops__mcp_ado_wit_update_work_item", "mcp__azure-devops__mcp_ado_wit_add_child_work_items", "mcp__azure-devops__mcp_ado_wit_work_items_link", "mcp__azure-devops__mcp_ado_wit_list_backlogs", "mcp__azure-devops__mcp_ado_wit_list_backlog_work_items", "mcp__azure-devops__mcp_ado_wit_get_work_items_for_iteration", "mcp__azure-devops__mcp_ado_wit_query_by_wiql", "mcp__azure-devops__mcp_ado_work_list_team_iterations", "mcp__azure-devops__mcp_ado_work_get_team_capacity", "mcp__azure-devops__mcp_ado_work_get_team_settings", "mcp__azure-devops__mcp_ado_repo_list_repos_by_project", "mcp__azure-devops__mcp_ado_repo_list_directory", "mcp__azure-devops__mcp_ado_repo_get_file_content", "mcp__azure-devops__mcp_ado_search_code", "mcp__azure-devops__mcp_ado_search_workitem", "mcp__azure-devops__mcp_ado_search_wiki", "mcp__azure-devops__mcp_ado_wiki_list_wikis", "mcp__azure-devops__mcp_ado_wiki_list_pages", "mcp__azure-devops__mcp_ado_wiki_get_page", "mcp__azure-devops__mcp_ado_wiki_get_page_content", "mcp__azure-devops__mcp_ado_wiki_create_or_update_page"]
---

Run the BA → SA → Architect → PM pipeline scoped to a single feature and create all child user stories in Azure DevOps under the parent epic.

## Arguments

- `$ARGUMENTS` — an ADO feature ID, or a feature description optionally followed by `under epic <ID>`

## Steps

### 1 — Load context

If `$ARGUMENTS` contains a feature ID, call `mcp_ado_wit_get_work_item` with that ID to retrieve the feature and its parent epic.

If only a description is given, ask: *"Which epic does this feature belong to? Provide the ADO epic ID."*

---

### 2 — BA phase

Use the **ba-agent** to decompose the feature into 2–6 user stories with Given/When/Then acceptance criteria and explicit out-of-scope boundaries.

Pass to the agent: feature title, description, parent epic context.

**Pause.** Ask: *"Do these stories cover the feature? Confirm or edit before architecture."*

---

### 3 — SA phase

Use the **sa-agent** to produce a feature-level technical design and per-story implementation notes.

Pass to the agent: feature context + BA output.

**Pause.** Ask: *"Does the technical approach look right? Confirm to proceed."*

---

### 4 — Architect phase

Use the **architect-agent** to write ADRs for significant decisions and audit cross-cutting concerns.

Pass to the agent: feature context + BA output + SA output.

**Pause.** Ask: *"Any architectural concerns before estimation?"*

---

### 5 — PM phase

Use the **pm-agent** to estimate story points, order stories, and assign to sprints.

Pass to the agent: all prior outputs.

**Pause.** Ask: *"Confirm to create items in Azure DevOps."*

---

### 6 — Create items in ADO

1. If no ADO Feature exists yet, call `mcp_ado_wit_add_child_work_items` with `parentId: <epic-id>`, `project`, `workItemType: "Feature"`, and `items` containing `title`, `description` (SA technical approach), and `format: "Markdown"`. If tags are needed, call `mcp_ado_wit_update_work_item` on the created feature ID with `/fields/System.Tags`.
2. For each User Story, call `mcp_ado_wit_add_child_work_items` with `parentId: <feature-id>`, `project`, `workItemType: "User Story"`, and `items` containing `title`, `description` (SA notes + Architect risks), `format: "Markdown"`, and `iterationPath`.
3. For each created story, call `mcp_ado_wit_update_work_item` with `updates` for `/fields/Microsoft.VSTS.Common.AcceptanceCriteria` and `/fields/Microsoft.VSTS.Scheduling.StoryPoints`.
4. For each ADR, call `mcp_ado_wiki_list_wikis` to get the wiki ID, optionally `mcp_ado_wiki_list_pages` to avoid number collisions, then call `mcp_ado_wiki_create_or_update_page` with `path: "/Architecture/ADRs/ADR-NNN-<slug>"`.

---

### 7 — Verify traceability

Read back each created item with `mcp_ado_wit_get_work_item` and confirm a parent link exists in the `relations` array. If any are missing, call `mcp_ado_wit_work_items_link` with `project` and `updates: [{ "id": <child-id>, "linkToId": <parent-id>, "type": "parent" }]`.

---

### 8 — Summary

| Type | Title | ADO ID | Parent | Sprint | Points |
|------|-------|--------|--------|--------|--------|
| Feature | ... | #N | #epic | — | — |
| Story | ... | #N | #feature | Sprint N | N |
