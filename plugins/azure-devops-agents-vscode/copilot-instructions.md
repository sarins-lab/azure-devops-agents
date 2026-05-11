# Azure DevOps Sprint Planning

Use the `azure-devops` MCP server for all Azure DevOps operations. The launcher reads `.ado-mcp.json` from the repo root to determine project and team automatically.

## Work Item Hierarchy

Epic -> Feature -> User Story -> Task

Always create items with parent links. Never leave a work item parentless.

## Planning Intent

When the user expresses planning intent, run the planning workflow directly. Recognize:
- `/plan-epic <id or description>`
- `/plan-feature <id or description>`
- `/plan-story <description> [under feature <id>]`
- Natural language such as "we need to", "we should", "let's", "I want to", "plan", "design", "build", "create", "define", "implement"

Do not trigger for lookup-only questions like "what's in sprint 3?" or "show me story #42".

## plan-story Workflow

Use this workflow for `/plan-story` or any request to plan one user story. Run it as a single-model workflow.

1. Load context. If the prompt contains `under feature <id>`, call `mcp_ado_wit_get_work_item` for that feature. If no feature is specified, ask for the ADO Feature ID before creating anything.
2. BA phase. Draft one story in `As a [persona] I want [goal] so that [value]` format with 2-4 Given/When/Then acceptance criteria covering happy path, edge case, and failure case. Include an explicit out-of-scope boundary. Pause and ask the user to edit or confirm.
3. SA phase. Add one implementation note covering what changes, which service owns it, how it integrates with adjacent services, and the key technical decision. Pause for confirmation.
4. PM phase. Estimate Fibonacci story points, recommend a sprint using `mcp_ado_work_list_team_iterations` and `mcp_ado_work_get_team_capacity`, and flag if the story should be split. Pause before creation.
5. Create only after confirmation. Call `mcp_ado_wit_add_child_work_items` with `parentId`, `project`, `workItemType: "User Story"`, and `items` containing exactly `title`, `description`, `format: "Markdown"`, and `iterationPath`.
6. Then call `mcp_ado_wit_update_work_item` for the created story ID with Acceptance Criteria and Story Points updates.
7. Read back with `mcp_ado_wit_get_work_item`. If the parent link is missing, call `mcp_ado_wit_work_items_link`.

## Tooling Rules

`mcp_ado_wit_add_child_work_items` only creates title, description, area path, iteration path, and parent link. Add Acceptance Criteria, Story Points, Tags, and other fields with `mcp_ado_wit_update_work_item`.

After creating any work item, verify the parent link with `mcp_ado_wit_get_work_item`. Fix missing links with `mcp_ado_wit_work_items_link`.
