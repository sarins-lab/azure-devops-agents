# plan-story

Create one Azure DevOps User Story under an existing Feature.

## Trigger

Use this workflow when the user types `/plan-story`, says `plan-story`, or asks to plan one user story.

Arguments: `<story-description> [under feature <feature-id>]`

## Workflow

1. Load context.
   If the prompt contains `under feature <id>`, call `mcp_ado_wit_get_work_item` for that Feature and use it as parent context.
   If no Feature ID is specified, ask for the ADO Feature ID before creating anything.

2. BA phase.
   Draft one story in `As a [persona] I want [goal] so that [value]` format.
   Include 2-4 Given/When/Then acceptance criteria covering happy path, edge case, and failure case.
   Include an explicit out-of-scope boundary.
   Pause and ask the user to edit or confirm.

3. SA phase.
   Add one implementation note covering what changes, which service owns it, how it integrates with adjacent services, and the key technical decision.
   Pause for confirmation.

4. PM phase.
   Estimate Fibonacci story points.
   Recommend a sprint using `mcp_ado_work_list_team_iterations` and `mcp_ado_work_get_team_capacity`.
   Flag if the story should be split.
   Pause before creating anything in ADO.

5. Create after confirmation.
   Call `mcp_ado_wit_add_child_work_items` with:
   - `parentId`: Feature ID
   - `project`: configured ADO project
   - `workItemType`: `"User Story"`
   - `items`: one item containing `title`, `description`, `format: "Markdown"`, and `iterationPath`

6. Enrich fields.
   Call `mcp_ado_wit_update_work_item` for the created story ID with:
   - `{ "op": "add", "path": "/fields/Microsoft.VSTS.Common.AcceptanceCriteria", "value": "<Given/When/Then acceptance criteria>" }`
   - `{ "op": "add", "path": "/fields/Microsoft.VSTS.Scheduling.StoryPoints", "value": "<points>" }`

7. Verify traceability.
   Read back with `mcp_ado_wit_get_work_item` and confirm the parent link exists in `relations`.
   If missing, call `mcp_ado_wit_work_items_link` with `updates: [{ "id": <story-id>, "linkToId": <feature-id>, "type": "parent" }]`.

8. Return the created story ID, title, points, sprint, and URL.

Do not use `mcp_ado_wit_add_child_work_items` to set Acceptance Criteria or Story Points directly.
Use `mcp_ado_wit_update_work_item` after creation.
