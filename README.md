# Azure DevOps Planning Assistant

This project helps your AI coding tools turn planning conversations into well-structured Azure DevOps work items.

After it is installed, you can describe work in plain English, such as:

> We need certificate rotation for internal services.

The assistant can then help break that idea into Azure DevOps Epics, Features, User Stories, acceptance criteria, technical notes, estimates, sprint suggestions, and Architecture Decision Records.

It works with:

- Claude Code
- VS Code with GitHub Copilot
- OpenAI Codex

## What It Does

The assistant follows the same planning process your delivery team would normally run:

| Step                | What happens                                                            |
| ------------------- | ----------------------------------------------------------------------- |
| Business analysis   | Turns an idea into clear user stories and acceptance criteria           |
| Technical planning  | Adds implementation notes and service-level design details              |
| Architecture review | Checks important risks and records architecture decisions               |
| Sprint planning     | Estimates work, splits oversized stories, and suggests sprint placement |

Nothing is created in Azure DevOps without confirmation. The assistant pauses after each major step so you can review, edit, or stop.

## What You Get

| Tool            | Result                                                |
| --------------- | ----------------------------------------------------- |
| Claude Code     | Full planning commands and specialist planning agents |
| VS Code Copilot | Planning instructions and reusable planning prompts   |
| Codex           | Planning instructions and `/plan-*` routing guidance  |

You can use natural language, or you can use one of these planning routes. In Claude Code these are native slash commands. In VS Code Copilot and Codex, use the same text in chat or from the installed prompt files.

| Command                       | Use it when                                                           |
| ----------------------------- | --------------------------------------------------------------------- |
| `/plan-epic <description>`    | You have a large initiative that needs to become features and stories |
| `/plan-feature <description>` | You have one feature that needs user stories                          |
| `/plan-story <description>`   | You need one user story with acceptance criteria and estimate         |

## Before You Install

You need:

- Access to your Azure DevOps organization
- Azure CLI installed and signed in
- Node.js 20 or later
- Bash on macOS/Linux, or PowerShell on Windows
- At least one supported AI tool: Claude Code, VS Code Copilot, or Codex

For a technical setup checklist, see [docs/install.MD](docs/install.MD).
For plugin package details, see [docs/plugin-packaging.MD](docs/plugin-packaging.MD).

Sign in to Azure first:

```powershell
az login
```

On Windows, this is also recommended:

```powershell
az config set core.enable_broker_on_windows=true
```

## Install

Set your Azure DevOps organization, then run the installer for your platform.

Windows PowerShell:

```powershell
$env:ADO_MCP_ORG = "<your-azure-devops-org>"
irm https://tinyurl.com/yc3wvu6u | iex
```

Linux/macOS:

```bash
export ADO_MCP_ORG="<your-azure-devops-org>"
curl -fsSL https://tinyurl.com/bdfuef4w | bash
```

After install, restart Codex, VS Code, or Claude Code so each tool reloads its
user-level MCP configuration.

For Codex-only installs, raw GitHub URLs, Docker/PAT mode, service principal
auth, or repo-local development installs, see [docs/install.MD](docs/install.MD).

## Connect A Repository To An Azure DevOps Project

In each code repository, add a file named `.ado-mcp.json` at the repository root:

```json
{
  "project": "YourProject",
  "team": "YourTeam"
}
```

This tells the assistant which Azure DevOps project and team to use for that repository.

## Daily Use

Open Claude Code, VS Code Copilot, or Codex in a repository that has `.ado-mcp.json`.

Then ask normally:

> We need to add self-service password reset.

or:

```text
/plan-feature add self-service password reset
```

The assistant will:

1. Ask clarifying questions if needed.
2. Draft the plan.
3. Pause for your approval.
4. Add technical and architecture notes.
5. Estimate the work.
6. Ask before creating anything in Azure DevOps.
7. Create the work items with parent-child links.

## Docker Option

If your team prefers Docker, you can run the Azure DevOps helper through Docker instead of local Node.js.

Build the image:

```powershell
docker build -t ghcr.io/sarins-lab/azure-devops-agents:latest .\docker
```

```bash
docker build -t ghcr.io/sarins-lab/azure-devops-agents:latest ./docker
```

Install using Docker mode:

```powershell
.\scripts\install.ps1 `
  -Organization <your-org> `
  -DockerImage ghcr.io/sarins-lab/azure-devops-agents:latest `
  -AuthToken <your-azure-devops-pat>
```

```bash
bash ./scripts/install.sh \
  --organization <your-org> \
  --docker-image ghcr.io/sarins-lab/azure-devops-agents:latest \
  --auth-token <your-azure-devops-pat>
```

Use Docker mode when you want each user's AI tool to run the same packaged helper environment.

## What The Installer Changes

The installer adds user-level configuration for the selected tools. It does not change your Azure DevOps projects by itself.

It creates or updates:

- Azure DevOps helper configuration under `~/.ado-mcp`
- Claude Code plugin and planning context
- Codex planning context under `~/.codex`
- VS Code Copilot planning prompts and settings

For Claude Code plugin installs, `.mcp.json` starts `scripts/ado-mcp-launcher.mjs`. That dispatcher starts PowerShell on Windows and Bash on macOS/Linux, so the plugin uses the same Azure DevOps MCP launcher on all supported operating systems.

## For Maintainers

The repo is organized so the planning logic is shared and each AI tool has its own adapter.

| Path                                                 | Purpose                                                               |
| ---------------------------------------------------- | --------------------------------------------------------------------- |
| `shared/workflows/`                                  | Main planning workflows                                               |
| `shared/mcp/`                                        | Azure DevOps tool rules                                               |
| `plugins/azure-devops-agents-claude/`                | Claude Code install context                                           |
| `plugins/azure-devops-agents-vscode/`                | VS Code Copilot instructions and prompts                              |
| `plugins/azure-devops-agents-codex/`                 | Codex instructions                                                    |
| `.claude-plugin/`, `commands/`, `agents/`, `skills/` | Claude Code plugin, commands, agents, skill, and marketplace metadata |

To add a new planning capability, update `shared/` first, then expose it through the relevant files under `plugins/`.

Useful validation commands:

```powershell
.\scripts\deploy.ps1
```

```bash
bash ./scripts/deploy.sh
```

By default, both deployment scripts run in dry-run mode. Pass `-Publish` on Windows or `--publish` on macOS/Linux only when you are ready to create and push release artifacts.

## DevSecOps Controls

The repository includes baseline DevSecOps checks through GitHub Actions:

- Validate workflow for plugin and prompt metadata integrity
- Security workflow for secret scanning, dependency review on pull requests, and Trivy vulnerability scanning
- Docker workflow with SBOM and provenance attestations for published container images

For stronger enforcement, protect the `main` branch and require successful checks from `Validate`, `Security`, and `Docker` before merge.

## License

[MIT](LICENSE)
