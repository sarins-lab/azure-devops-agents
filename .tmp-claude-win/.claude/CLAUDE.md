
<!-- azure-devops-agents: start -->
# Azure DevOps - Sprint Planning (azure-devops-agents)

The `azure-devops` MCP server is registered at user level. Place `.ado-mcp.json` in any repo root to specify `project` and `team`; the launcher injects them automatically.

## Work Item Hierarchy

Epic -> Feature -> User Story -> Task

All items must be created with parent links. Never leave a work item parentless.

## Automatic Planning Pipeline

Run the BA->SA->Architect->PM pipeline automatically whenever the user expresses planning intent. Do not wait for an explicit command.

Trigger phrases: "we need to", "we should", "let's", "I want to", "plan", "design", "build", "create", "define", "implement".

Do not trigger for lookup-only queries such as "what's in sprint 3?" or "show me story #42".

Use Claude specialist agents for each phase:

| Signal | Level | Agents |
|--------|-------|--------|
| Epic, broad initiative, multiple features | Epic | ba-agent -> sa-agent -> architect-agent -> pm-agent |
| Feature, specific capability | Feature | ba-agent -> sa-agent -> architect-agent -> pm-agent |
| User story, single behavior | Story | ba-agent -> sa-agent -> pm-agent |
| Ambiguous | Ask | "Are we planning an Epic, a Feature, or a User Story?" |

Pause for user confirmation after each agent phase before proceeding.

## Tooling Rules

Use `mcp_ado_wit_add_child_work_items` only for title, description, area path, iteration path, and parent link. Add Acceptance Criteria, Story Points, Tags, and other fields afterward with `mcp_ado_wit_update_work_item`.

After creating any work item, verify the parent link with `mcp_ado_wit_get_work_item`. Fix missing links with `mcp_ado_wit_work_items_link`.

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
<!-- azure-devops-agents: end -->
