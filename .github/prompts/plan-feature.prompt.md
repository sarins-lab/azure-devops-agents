---
name: plan-feature
description: Plan one Azure DevOps feature, decompose it into user stories, add implementation notes and ADRs, estimate, and create traced work items.
argument-hint: <feature-id or feature-description> [under epic <epic-id>]
agent: agent
tools: ["azure-devops/*"]
---

Run the BA, SA, Architect, and PM planning workflow for a single Feature.

If the input contains a Feature ID, call `mcp_ado_wit_get_work_item` for that Feature and use its parent Epic as context. If only a description is given, ask for the parent Epic ID before creating anything.

Workflow:

1. BA phase: decompose the Feature into 2-6 User Stories with Given/When/Then acceptance criteria and explicit out-of-scope boundaries. Pause for confirmation.
2. SA phase: produce a feature-level technical design and per-story implementation notes. Ground the design with `mcp_ado_repo_list_repos_by_project`, `mcp_ado_repo_list_directory`, and relevant file reads. Pause for confirmation.
3. Architect phase: read prior ADRs using `mcp_ado_wiki_list_wikis`, `mcp_ado_wiki_list_pages`, `mcp_ado_wiki_get_page`, and `mcp_ado_wiki_get_page_content`. Write ADRs for significant decisions and audit cross-cutting concerns. Pause for confirmation.
4. PM phase: estimate story points, order by dependency and value, and assign stories to sprints using team iteration and capacity tools. Pause before creating anything in ADO.
5. After confirmation, create the Feature if needed with `mcp_ado_wit_add_child_work_items` under the Epic.
6. Create User Stories with `mcp_ado_wit_add_child_work_items` under the Feature.
7. Add Acceptance Criteria and Story Points with `mcp_ado_wit_update_work_item`.
8. Create ADR pages with `mcp_ado_wiki_create_or_update_page`.
9. Read back every created work item with `mcp_ado_wit_get_work_item`; repair missing parent links with `mcp_ado_wit_work_items_link`.

Return a summary table with type, title, ADO ID, parent, sprint, and points.
