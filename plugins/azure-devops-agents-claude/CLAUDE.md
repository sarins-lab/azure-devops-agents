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
