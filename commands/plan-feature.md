---
description: Run the BA → SA → Architect → PM pipeline for a single feature. Decomposes it into stories, adds technical design and ADRs, estimates, and creates everything in Azure DevOps.
argument-hint: <feature-id or feature-description> [under epic <epic-id>]
allowed-tools: ["mcp__azure-devops__wit_work_item", "mcp__azure-devops__wit_work_item_write", "mcp__azure-devops__wit_work_item_link_write", "mcp__azure-devops__wiki", "mcp__azure-devops__wiki_upsert_page", "mcp__azure-devops__work_list_team_iterations", "mcp__azure-devops__work_get_team_capacity", "mcp__azure-devops__wit_backlog"]
---

Run the BA → SA → Architect → PM pipeline scoped to a single feature and create all child user stories in Azure DevOps under the parent epic.

## Arguments

- `$ARGUMENTS` — an ADO feature ID, or a feature description optionally followed by `under epic <ID>`

## Steps

### 1 — Load context

If `$ARGUMENTS` contains a feature ID, call `wit_work_item` with that ID to retrieve the feature and its parent epic.

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

1. If no ADO Feature exists yet, call `wit_work_item_write` with `type: "Feature"` and the required fields, then call `wit_work_item_link_write` with `sourceId: <feature-id>`, `targetId: <epic-id>`, `linkType: "System.LinkTypes.Hierarchy-Reverse"` to set the parent.
2. For each User Story, call `wit_work_item_write` with `type: "User Story"` and all required fields, then call `wit_work_item_link_write` to link it to the feature.
3. For each ADR, call `wiki` with `action: "list"` to get the wiki ID, then call `wiki_upsert_page` with `path: "/Architecture/ADRs/ADR-NNN-<slug>"` and the Markdown content.

---

### 7 — Verify traceability

Read back each created item with `wit_work_item` and confirm a parent link exists in the `relations` array. Fix any missing links with `wit_work_item_link_write`.

---

### 8 — Summary

| Type | Title | ADO ID | Parent | Sprint | Points |
|------|-------|--------|--------|--------|--------|
| Feature | ... | #N | #epic | — | — |
| Story | ... | #N | #feature | Sprint N | N |
