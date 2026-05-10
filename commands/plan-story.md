---
description: Create a single user story with Given/When/Then acceptance criteria, SA implementation notes, and a Fibonacci story point estimate in Azure DevOps.
argument-hint: <story-description> [under feature <feature-id>]
allowed-tools: ["mcp__azure-devops__wit_work_item", "mcp__azure-devops__wit_work_item_write", "mcp__azure-devops__work_list_team_iterations", "mcp__azure-devops__work_get_team_capacity"]
---

Create a single well-formed user story with acceptance criteria, SA implementation notes, and a story point estimate, then write it to Azure DevOps under the specified feature.

## Arguments

- `$ARGUMENTS` — a story description or intent, optionally followed by `under feature <ID>`

## Steps

### 1 — Load context

If a feature ID is given, call `wit_work_item` (action: `get`) to retrieve the feature and its parent epic for full context.

If no feature is specified, ask: *"Which feature does this story belong to? Provide the ADO feature ID."*

---

### 2 — BA phase

Use the **ba-agent** to write the story in "As a [persona] I want [goal] so that [value]" format with:
- 2–4 Given/When/Then acceptance criteria covering the happy path, an edge case, and a failure case
- An explicit out-of-scope boundary

**Pause.** Show the story and AC. Ask: *"Does this capture the intent? Edit or confirm."*

---

### 3 — SA + estimate

Use the **sa-agent** to add a one-paragraph implementation note.

Use the **pm-agent** to:
- Estimate story points (Fibonacci)
- Recommend a sprint using `work_list_team_iterations`
- Flag if the story should be split

**Pause.** Show the complete story card. Ask: *"Confirm to create in Azure DevOps."*

---

### 4 — Create in ADO

Create the story as a child of the feature with `wit_work_item_write` (action: `add_child`):
- `System.Title`
- `Microsoft.VSTS.Common.AcceptanceCriteria`
- `System.Description` (SA implementation note)
- `Microsoft.VSTS.Scheduling.StoryPoints`
- `System.IterationPath`

---

### 5 — Verify and confirm

Read back the created item with `wit_work_item` (action: `get`) and confirm the parent link is present.

Report: `Story #<ID> created — https://dev.azure.com/sarins-lab/Platform/_workitems/edit/<id>`
