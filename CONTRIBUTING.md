# Contributing

## What you can contribute

- **New agents** — add a specialist to the pipeline (e.g. a Security Reviewer or API Designer)
- **Improved agent prompts** — better cross-cutting checklists, more precise output formats, sharper behavioural guardrails
- **New RUP routes** — additional planning intents inside the primary tool instruction files
- **Bug reports** — agent output that is incorrect, hallucinated, or violates the output format contract
- **Documentation** — setup guides, worked examples, platform-specific notes

## Package authoring rules

Shared behavior belongs in `shared/` first:

- Add canonical workflow changes to `shared/workflows/`
- Add Azure DevOps MCP tool rules to `shared/mcp/`
- Then expose the behavior in the relevant package under `plugins/azure-devops-agents-claude/`, `plugins/azure-devops-agents-vscode/`, or `plugins/azure-devops-agents-codex/`

Do not fork the planning logic independently per client. Each tool should have one primary instruction surface and should route into `shared/workflows/rup-planning.md`.

## Agent authoring rules

Each agent file in `agents/` must follow this structure:

```
---
name: <agent-name>
description: <one-line description — used for routing, be specific>
model: inherit
color: <blue|cyan|magenta|yellow|green|red|orange>
tools: ["mcp__plugin_azure-devops-agents-claude_azure-devops__*", "mcp__azure-devops__<tool>", ...]
---

Trigger this agent when:
- <condition>

<example>
Context: ...
user: "..."
assistant: "..."
<commentary>...</commentary>
</example>

[System prompt body]
```

Rules:

- `description` must be a single short line — no examples inside the YAML block
- `tools` should include the Claude plugin-scoped wildcard `mcp__plugin_azure-devops-agents-claude_azure-devops__*` and any user-level `mcp__azure-devops__<official-tool-name>` entries needed for direct MCP installs. The official tool name starts with `mcp_ado_`.
- Examples go in the body after the closing `---`, not inside the description
- Every agent must define a step-by-step process, an explicit output format, and behavioural guardrails

## Route authoring rules

Add new route behavior to the primary client instruction files and the shared RUP workflow. Do not add separate command or prompt files for process-specific route names.

## Testing

There is no automated test suite. Test by running the commands against a real Azure DevOps project:

1. Set up the MCP and client adapters: `.\scripts\install.ps1 -Organization <your-org>`
2. Copy `.ado-mcp.example.json` to `.ado-mcp.json` and fill in your test project
3. Run `/capture-request "a simple stakeholder request"` and verify the output format

## Pull requests

- One PR per agent, route, or workflow change
- Include a brief description of what the role or route does differently and why
- If changing the output format of an agent, update any downstream agents that parse it
