# Azure DevOps RUP Planning Assistant

This project helps AI coding tools turn planning conversations into RUP-style SDLC artifacts and then persist them into Azure DevOps.

The planning vocabulary is RUP language:

- Stakeholder Request
- Functional Requirement
- Non-Functional Requirement
- UX Artifact
- Technical Requirement
- Architecture
- Technical Documentation
- Delivery Slice
- Task

Azure DevOps process terms such as CMMI Requirement, Scrum Product Backlog Item, Agile User Story, or Basic Issue are selected only at write time after the assistant reads the target project metadata.

Supported clients:

- Claude Code
- VS Code with GitHub Copilot
- OpenAI Codex

## What It Does

| SDLC role | Output |
| --- | --- |
| Stakeholder Analyst | Stakeholder request, scope, business value, affected users, success measures |
| Requirements Analyst | Functional and non-functional requirements with acceptance criteria |
| UX Designer | User journeys, screen flows, Figma-ready screen specifications, accessibility notes, UX acceptance criteria |
| Solution Architect | Cohesive architecture views, boundaries, runtime flows, deployment, data, security, operations, technical requirements, ADR candidates |
| Technical Writer | Traceable technical documentation and Azure DevOps wiki-safe Mermaid diagrams from confirmed architecture |
| Delivery Planner | Delivery slices, estimates, dependency order, sprint or iteration recommendation |
| Implementation Lead | Task breakdown with sequencing and done criteria |

Nothing is created in Azure DevOps without confirmation.

## Routes

Preferred routes:

| Route | Use it when |
| --- | --- |
| `/capture-request <description>` | Capture a stakeholder request or change need |
| `/define-requirements <request>` | Derive functional and non-functional requirements |
| `/design-ux <requirements>` | Produce UX flow, screen specs, Figma guidance, and UX acceptance criteria |
| `/plan-requirement <description>` | Refine one requirement |
| `/document-solution <requirements or architecture>` | Produce technical documentation and diagrams |
| `/plan-delivery <requirement>` | Produce delivery slices, estimates, and iteration placement |
| `/plan-task <delivery-slice>` | Produce implementation tasks |

Natural planning intent should also trigger the workflow. For example, "I want to setup a highly secure home lab exposed through Cloudflare Tunnel" maps to `/capture-request` and starts the Stakeholder Analyst phase.

## Development Readiness Gate

Development does not start until the request is traceable to an existing approved Azure DevOps work item or a confirmed RUP planning artifact. If the user asks for work that is not already represented in Azure DevOps, the assistant captures it as a new Stakeholder Request or Change Request and runs the SDLC workflow first.

User-facing work must include the UX Designer phase before development starts, unless UX is explicitly marked not applicable for non-UI work.

## Architecture Quality

Architecture is not a technology list. It must define system boundary, actors, components, runtime flows, deployment, data, security, operations, decisions, tradeoffs, and open questions. Technical documentation must use the confirmed architecture and Azure DevOps wiki-safe Mermaid diagrams: `::: mermaid` blocks and `graph TD;` or `graph LR;` for flowcharts.

## Azure DevOps Mapping

Before writing work items, the assistant:

1. Calls `mcp_ado_wit_list_backlogs`.
2. Reads target work item type metadata with `mcp_ado_wit_get_work_item_type`.
3. Chooses valid fields for estimates, acceptance criteria, requirement classification, tags, and iteration.
4. Creates parent-before-child with `mcp_ado_wit_add_child_work_items`.
5. Updates only discovered fields with `mcp_ado_wit_update_work_item`.
6. Verifies traceability with `mcp_ado_wit_get_work_item`.

## Install

Pass the Azure DevOps organization during install. Pass the default project and optional team as well when you want a fully noninteractive setup.

Online install:

Windows PowerShell:

```powershell
$env:ADO_MCP_ORG = "<your-azure-devops-org>"
$env:ADO_MCP_PROJECT = "<your-default-project>"
$env:ADO_MCP_TEAM = "<your-default-team>"   # optional
$env:ADO_MCP_CLIENTS = "All"                # optional: All, Claude, VSCode, Codex
$env:ADO_MCP_FORCE = "1"                    # optional: replace existing config blocks
irm https://tinyurl.com/yc3wvu6u | iex
```

Linux/macOS:

```bash
export ADO_MCP_ORG="<your-azure-devops-org>"
export ADO_MCP_PROJECT="<your-default-project>"
export ADO_MCP_TEAM="<your-default-team>"   # optional
export ADO_MCP_CLIENTS="All"                # optional: All, Claude, VSCode, Codex
export ADO_MCP_FORCE="1"                    # optional: replace existing config blocks
curl -fsSL https://tinyurl.com/bdfuef4w | bash
```

Repo-local install:

```powershell
.\scripts\install.ps1 -Organization <your-azure-devops-org> -Project <your-default-project> -Team "<your-default-team>"
```

```bash
bash ./scripts/install.sh --organization <your-azure-devops-org> --project <your-default-project> --team "<your-default-team>"
```

If project and team are omitted, the installer prompts for them. Use `-Clients` or `--clients` to limit configuration to one tool, and `-Force` or `--force` to replace existing matching config.

After install, restart Codex, VS Code, or Claude Code so each tool reloads its user-level MCP configuration.

## Project Binding

During install, provide a default Azure DevOps project and optional team. They are stored in `~/.ado-mcp/config.json` and used for repos that do not define their own binding.

In a code repository, add `.ado-mcp.json` at the repository root only when that repo should override the user-level default:

```json
{
  "project": "YourProject",
  "team": "YourTeam"
}
```

The launcher resolves project and team as: repo `.ado-mcp.json` first, then user-level `~/.ado-mcp/config.json`, then environment variables.

## Maintainers

Canonical planning workflow: `shared/workflows/rup-planning.md`.

Azure DevOps MCP contract: `shared/mcp/azure-devops-tools.md`.

Primary client instruction files:

- Codex: `plugins/azure-devops-agents-codex/AGENTS.md`
- Claude Code: `plugins/azure-devops-agents-claude/CLAUDE.md`
- VS Code Copilot: `plugins/azure-devops-agents-vscode/copilot-instructions.md`

Do not add separate command or prompt files for process-specific route names.
