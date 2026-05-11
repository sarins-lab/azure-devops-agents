---
name: plan-story
description: Create one Azure DevOps user story with acceptance criteria, implementation notes, estimate, sprint recommendation, and parent traceability.
argument-hint: <story-description> [under feature <feature-id>]
agent: agent
tools: ["azure-devops/*"]
---

Create a single well-formed Azure DevOps User Story under the specified Feature.

If the chat input contains `under feature <id>`, call `mcp_ado_wit_get_work_item` for that Feature and use it as parent context. If no Feature ID is specified, ask the user for the ADO Feature ID before creating anything.

Run the workflow as a single model:

1. BA phase: write one story in "As a [persona] I want [goal] so that [value]" format with 2-4 Given/When/Then acceptance criteria covering happy path, edge case, and failure case. Include an explicit out-of-scope boundary. Pause and ask the user to edit or confirm.
2. SA phase: add one implementation note covering what changes, which service owns it, how it integrates with adjacent services, and the key technical decision. Pause for confirmation.
3. PM phase: estimate Fibonacci story points, recommend a sprint using `mcp_ado_work_list_team_iterations` and `mcp_ado_work_get_team_capacity`, and flag if the story should be split. Pause before creating anything in ADO.
4. After confirmation, call `mcp_ado_wit_add_child_work_items` with:
   - `parentId`: the Feature ID
   - `project`: the configured ADO project
   - `workItemType`: `"User Story"`
   - `items`: one item containing `title`, `description`, `format: "Markdown"`, and `iterationPath`
5. Then call `mcp_ado_wit_update_work_item` for the created story ID with:
   - `{ "op": "add", "path": "/fields/Microsoft.VSTS.Common.AcceptanceCriteria", "value": "<Given/When/Then acceptance criteria>" }`
   - `{ "op": "add", "path": "/fields/Microsoft.VSTS.Scheduling.StoryPoints", "value": "<points>" }`
6. Read back the story with `mcp_ado_wit_get_work_item` and confirm the parent link exists in `relations`. If missing, call `mcp_ado_wit_work_items_link` with `updates: [{ "id": <story-id>, "linkToId": <feature-id>, "type": "parent" }]`.
7. Return the created story ID, title, points, sprint, and URL.

Do not use `mcp_ado_wit_add_child_work_items` to set Acceptance Criteria or Story Points directly; use `mcp_ado_wit_update_work_item` after creation.
