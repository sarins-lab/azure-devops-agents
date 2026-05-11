# Azure DevOps MCP Tooling

Use Microsoft's official `@azure-devops/mcp` package through the `azure-devops` MCP server.

Tool names use the `mcp_ado_*` naming pattern.

## Work Item Creation

`mcp_ado_wit_add_child_work_items` creates child work items and parent links. It supports title, description, area path, iteration path, and Markdown/HTML format.

It does not set fields such as Acceptance Criteria, Story Points, or Tags. Add those afterward with `mcp_ado_wit_update_work_item`.

Use `mcp_ado_wit_work_items_link` only to repair or add links after creation.

## Backlog Lookup

Call `mcp_ado_wit_list_backlogs` first to get the backlog ID, then call `mcp_ado_wit_list_backlog_work_items` with `project`, `team`, and `backlogId`.

## Wiki Lookup

Use this sequence:

1. `mcp_ado_wiki_list_wikis`
2. `mcp_ado_wiki_list_pages`
3. `mcp_ado_wiki_get_page`
4. `mcp_ado_wiki_get_page_content`

`mcp_ado_wiki_get_page` returns metadata. `mcp_ado_wiki_get_page_content` returns the page text.
