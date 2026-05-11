# plan-feature

Run the BA, SA, Architect, and PM planning flow for one Feature, then create linked Azure DevOps work items.

## Trigger

Use this workflow when the user types `/plan-feature`, says `plan-feature`, or asks to plan a specific capability.

Arguments: `<feature-id or feature-description> [under epic <epic-id>]`

## Workflow

1. Load context.
   If a Feature ID is provided, call `mcp_ado_wit_get_work_item` for the Feature and parent Epic.
   If only a description is provided, ask for the parent Epic ID before creating anything.

2. BA phase.
   Decompose the Feature into 2-6 User Stories with Given/When/Then acceptance criteria and explicit out-of-scope boundaries.
   Pause for confirmation.

3. SA phase.
   Produce a feature-level technical design and per-story implementation notes.
   Use `mcp_ado_repo_list_repos_by_project`, `mcp_ado_repo_list_directory`, and relevant `mcp_ado_repo_get_file_content` calls to ground the design.
   Pause for confirmation.

4. Architect phase.
   Read prior ADR context with `mcp_ado_wiki_list_wikis`, `mcp_ado_wiki_list_pages`, `mcp_ado_wiki_get_page`, and `mcp_ado_wiki_get_page_content`.
   Write ADRs for significant decisions and audit cross-cutting concerns.
   Pause for confirmation.

5. PM phase.
   Estimate story points, order by dependency and value, and assign stories to sprints using team iteration and capacity tools.
   Pause before creating anything in ADO.

6. Create items.
   If the Feature does not already exist, call `mcp_ado_wit_add_child_work_items` with `parentId: <epic-id>`, `project`, `workItemType: "Feature"`, and `items` containing `title`, `description`, and `format: "Markdown"`.
   For each User Story, call `mcp_ado_wit_add_child_work_items` with `parentId: <feature-id>`, `project`, `workItemType: "User Story"`, and `items` containing `title`, `description`, `format: "Markdown"`, and `iterationPath`.
   Then call `mcp_ado_wit_update_work_item` for Acceptance Criteria and Story Points.
   Create ADR pages with `mcp_ado_wiki_create_or_update_page`.

7. Verify traceability.
   Read back every created work item with `mcp_ado_wit_get_work_item`.
   Fix missing parent links with `mcp_ado_wit_work_items_link`.
