# plan-epic

Run the full BA, SA, Architect, and PM planning flow for an Epic, then create linked Azure DevOps Features, User Stories, and ADR pages.

## Trigger

Use this workflow when the user types `/plan-epic`, says `plan-epic`, or asks to plan a broad initiative with multiple capabilities.

Arguments: `<epic-id or epic-description>`

## Workflow

1. Load context.
   If an Epic ID is provided, call `mcp_ado_wit_get_work_item` for the Epic.
   If only a description is provided, ask whether to create a new Epic or plan against an existing Epic.

2. BA phase.
   Decompose the Epic into Features and User Stories with Given/When/Then acceptance criteria.
   Pause for confirmation.

3. SA phase.
   Add technical design to each Feature and implementation notes to each Story.
   Ground the design in repositories using official repo tools.
   Pause for confirmation.

4. Architect phase.
   Read existing ADRs with the wiki tool sequence: list wikis, list pages, get page metadata, get page content.
   Write new ADRs and cross-cutting concern findings.
   Pause for confirmation.

5. PM phase.
   Estimate story points, order by dependency and value, and assign stories to sprints.
   Use team iteration and capacity tools before assignment.
   Pause before creating anything in ADO.

6. Create items parent-before-child.
   Features: `mcp_ado_wit_add_child_work_items` under the Epic.
   User Stories: `mcp_ado_wit_add_child_work_items` under each Feature.
   Story fields: `mcp_ado_wit_update_work_item` for Acceptance Criteria and Story Points.
   ADRs: `mcp_ado_wiki_create_or_update_page` under `/Architecture/ADRs/ADR-NNN-<slug>`.

7. Verify traceability.
   Read back every created work item with `mcp_ado_wit_get_work_item`.
   Fix missing parent links with `mcp_ado_wit_work_items_link`.
