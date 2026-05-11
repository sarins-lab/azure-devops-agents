# Azure DevOps - Sprint Planning (azure-devops-agents)

The `azure-devops` MCP server is configured at user level via `~/.codex/config.toml`.
Place `.ado-mcp.json` in any repo root to specify `project` and `team`; the launcher injects them automatically.

## Work Item Hierarchy

Epic -> Feature -> User Story -> Task

All items must be created with parent links. Never leave a work item parentless.

## Routing

Run the planning workflow automatically when planning intent is detected. Do not wait for an explicit command.

Also recognize slash-style text commands typed by the user:
- `/plan-story <description> [under feature <id>]`
- `/plan-feature <id or description>`
- `/plan-epic <id or description>`

Codex does not load Claude command files. Treat these slash-style inputs as routing instructions and execute the workflow directly; do not say the command is unavailable.

Trigger phrases: "we need to", "we should", "let's", "I want to", "plan", "design", "build", "create", "define", "implement".

Do not trigger for lookup-only queries such as "what's in sprint 3?" or "show me story #42".

Detect level from context: Epic for broad initiatives, Feature for specific capabilities, Story for single behavior. Ask if ambiguous.

## Canonical Workflows

For plan-story, follow the workflow in `shared/workflows/plan-story.md`.
For plan-feature, follow the workflow in `shared/workflows/plan-feature.md`.
For plan-epic, follow the workflow in `shared/workflows/plan-epic.md`.

If the shared files are not available in the current context, use the embedded rules below.

## plan-story Workflow

1. Load context. If the prompt contains `under feature <id>`, call `mcp_ado_wit_get_work_item` for that Feature. If no Feature ID is specified, ask for it before creating anything.
2. BA phase. Draft one story in `As a [persona] I want [goal] so that [value]` format with 2-4 Given/When/Then acceptance criteria and an explicit out-of-scope boundary. Pause for confirmation.
3. SA phase. Add one implementation note covering what changes, which service owns it, how it integrates, and the key technical decision. Pause for confirmation.
4. PM phase. Estimate Fibonacci story points, recommend a sprint using `mcp_ado_work_list_team_iterations` and `mcp_ado_work_get_team_capacity`, and flag if the story should be split. Pause before creating anything.
5. Create only after confirmation. Call `mcp_ado_wit_add_child_work_items` with `parentId`, `project`, `workItemType: "User Story"`, and `items` containing exactly `title`, `description`, `format: "Markdown"`, and `iterationPath`.
6. Then call `mcp_ado_wit_update_work_item` for the created story ID with Acceptance Criteria and Story Points updates.
7. Read back with `mcp_ado_wit_get_work_item`. If the parent link is missing, call `mcp_ado_wit_work_items_link`.

## Tooling Rules

Use the official create-then-update pattern. `mcp_ado_wit_add_child_work_items` only creates title, description, area path, iteration path, and parent link. Add Acceptance Criteria, Story Points, Tags, and other fields with `mcp_ado_wit_update_work_item`.

Read prior ADRs with `mcp_ado_wiki_list_wikis`, `mcp_ado_wiki_list_pages`, `mcp_ado_wiki_get_page`, and `mcp_ado_wiki_get_page_content`.

Verify every created item with `mcp_ado_wit_get_work_item`. Fix missing links with `mcp_ado_wit_work_items_link`.
