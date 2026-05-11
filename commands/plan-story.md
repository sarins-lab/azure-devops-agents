---
description: Create a single user story with Given/When/Then acceptance criteria, SA implementation notes, and a Fibonacci story point estimate in Azure DevOps.
argument-hint: <story-description> [under feature <feature-id>]
allowed-tools: ["mcp__plugin_azure-devops-agents-claude_azure-devops__*", "mcp__azure-devops__mcp_ado_wit_get_work_item", "mcp__azure-devops__mcp_ado_wit_add_child_work_items", "mcp__azure-devops__mcp_ado_wit_update_work_item", "mcp__azure-devops__mcp_ado_wit_work_items_link", "mcp__azure-devops__mcp_ado_wit_query_by_wiql", "mcp__azure-devops__mcp_ado_work_list_team_iterations", "mcp__azure-devops__mcp_ado_work_get_team_capacity", "mcp__azure-devops__mcp_ado_work_get_team_settings", "mcp__azure-devops__mcp_ado_search_workitem"]
---

Create a single well-formed user story with acceptance criteria, SA implementation notes, and a story point estimate, then write it to Azure DevOps under the specified feature.

## Arguments

- `$ARGUMENTS` — a story description or intent, optionally followed by `under feature <ID>`

## Steps

### 1 — Load context

If a feature ID is given, call `mcp_ado_wit_get_work_item` with that ID to retrieve the feature and its parent epic for full context.

If no feature is specified, ask: *"Which feature does this story belong to? Provide the ADO feature ID."*

---

### 2 — BA phase

Use the **ba-agent** to write the story in "As a [persona] I want [goal] so that [value]" format with:
- 2–4 Given/When/Then acceptance criteria covering the happy path, an edge case, and a failure case
- An explicit out-of-scope boundary

**Pause.** Show the story and AC. Ask: *"Does this capture the intent? Edit or confirm."*

---

### 3 — SA phase

Use the **sa-agent** to add a one-paragraph implementation note covering what changes, which service owns it, how it integrates with adjacent services, and the key technical decision the implementer must get right.

**Pause.** Show the implementation note. Ask: *"Does the technical approach look right? Confirm to proceed to estimation."*

---

### 4 — PM phase

Use the **pm-agent** to:
- Estimate story points (Fibonacci)
- Recommend a sprint using `mcp_ado_work_list_team_iterations` and `mcp_ado_work_get_team_capacity`
- Flag if the story should be split

**Pause.** Show the complete story card with estimate and sprint assignment. Ask: *"Confirm to create in Azure DevOps."*

---

### 5 — Create in ADO

Call `mcp_ado_wit_add_child_work_items` with:
- `parentId`: the feature ID
- `project`: the configured ADO project
- `workItemType`: `"User Story"`
- `items`: one item with `title`, `description` (SA implementation note), `format: "Markdown"`, and `iterationPath`

This creates the story and sets the parent link in one call.

Then call `mcp_ado_wit_update_work_item` for the created story ID with `updates`:
- `{ "op": "add", "path": "/fields/Microsoft.VSTS.Common.AcceptanceCriteria", "value": "<Given/When/Then acceptance criteria>" }`
- `{ "op": "add", "path": "/fields/Microsoft.VSTS.Scheduling.StoryPoints", "value": "<points>" }`

---

### 6 — Verify and confirm

Read back the created item with `mcp_ado_wit_get_work_item` and confirm the parent link is present in the `relations` array.
If the parent link is missing, call `mcp_ado_wit_work_items_link` with `project` and `updates: [{ "id": <story-id>, "linkToId": <feature-id>, "type": "parent" }]`.

Construct the item URL from the ADO org and project in `.ado-mcp.json`: `https://dev.azure.com/<org>/<project>/_workitems/edit/<story-id>`
