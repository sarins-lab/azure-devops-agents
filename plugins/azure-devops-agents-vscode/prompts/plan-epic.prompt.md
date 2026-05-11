---
name: plan-epic
description: Run the full Azure DevOps epic planning pipeline and create linked features, user stories, and ADR pages.
argument-hint: <epic-id or epic-description>
agent: agent
tools: ["azure-devops/*"]
---

Run the full BA, SA, Architect, and PM planning workflow for an Epic.

If the input is an Epic ID, call `mcp_ado_wit_get_work_item` and use the Epic title, description, and acceptance criteria as planning context. If the input is only a description, ask whether to create a new Epic work item or plan against an existing Epic before creating anything.

Workflow:

1. BA phase: decompose the Epic into Features and User Stories with Given/When/Then acceptance criteria. Pause for confirmation.
2. SA phase: add technical design to each Feature and implementation notes to each Story. Ground the design in repositories using official repo tools. Pause for confirmation.
3. Architect phase: read existing ADRs with `mcp_ado_wiki_list_wikis`, `mcp_ado_wiki_list_pages`, `mcp_ado_wiki_get_page`, and `mcp_ado_wiki_get_page_content`; write new ADRs and cross-cutting concern findings. Pause for confirmation.
4. PM phase: estimate story points, order by dependency and value, and assign stories to sprints using team iteration and capacity tools. Pause before creating anything in ADO.
5. After confirmation, create Features with `mcp_ado_wit_add_child_work_items` under the Epic.
6. Create User Stories with `mcp_ado_wit_add_child_work_items` under each Feature.
7. Add Acceptance Criteria and Story Points with `mcp_ado_wit_update_work_item`.
8. Create ADR pages with `mcp_ado_wiki_create_or_update_page` under `/Architecture/ADRs/ADR-NNN-<slug>`.
9. Read back every created work item with `mcp_ado_wit_get_work_item`; repair missing parent links with `mcp_ado_wit_work_items_link`.

Return a summary table with type, title, ADO ID, parent, sprint, points, and Epic URL.
