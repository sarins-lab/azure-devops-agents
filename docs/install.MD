# Technical Install Requirements

This guide is for people setting up or supporting the Azure DevOps Planning Assistant across Claude Code, VS Code Copilot, and Codex.

The project uses Microsoft's official `@azure-devops/mcp` package. The MCP transport is stdio. In Docker mode, Docker is used as a local stdio wrapper; this is not a central HTTP server.

## Required Access

The installing user needs access to the target Azure DevOps organization and enough permissions for the planning workflow:

- Read projects, teams, iterations, and team capacity
- Read and create work items
- Update work item fields such as Acceptance Criteria, Story Points, Tags, and Iteration Path
- Create parent-child work item links
- Read repositories for technical discovery
- Read and update wiki pages for ADRs

The repo using this plugin must contain `.ado-mcp.json`:

```json
{
  "project": "YourProject",
  "team": "YourTeam"
}
```

The launcher reads this file at runtime and injects the Azure DevOps project and team for the MCP server.

## Supported Clients

| Client          | Required for install                                             | What gets configured                                                      |
| --------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Claude Code     | `claude` CLI on `PATH`                                           | MCP server, plugin marketplace, native plugin, global `CLAUDE.md` context |
| VS Code Copilot | VS Code user settings directory and Copilot Chat                 | MCP server, Copilot instructions, prompt files                            |
| Codex           | Codex config directory; `codex` CLI recommended for verification | MCP server in `~/.codex/config.toml`, global `AGENTS.md` context          |

If the Claude CLI is missing, the installer still writes Claude context, but MCP registration and plugin install must be completed manually after Claude Code is installed.

## Runtime Requirements

Default local mode requires:

- Windows: Windows PowerShell 5.1 or PowerShell 7+
- macOS/Linux: Bash
- Azure CLI
- Successful `az login`
- Node.js 20+
- Network access to `dev.azure.com`
- Network access to the npm registry so `npx @azure-devops/mcp` can run

Docker mode requires:

- Docker Desktop or Docker Engine
- A Docker image that packages `@azure-devops/mcp`
- Azure DevOps PAT available through `ADO_MCP_AUTH_TOKEN` or installer `-AuthToken`
- Network access to `dev.azure.com`
- Network access to the container registry if the image must be pulled

## Authentication Options

### Azure CLI mode

This is the default mode.

```powershell
az login
.\scripts\install.ps1 -Organization <your-org>
```

```bash
az login
bash ./scripts/install.sh --organization <your-org>
```

The launcher starts `@azure-devops/mcp` through `npx` and uses the active Azure CLI session.

### Docker PAT mode

Use this when you want every client to run the same packaged MCP environment.

```powershell
docker build -t ghcr.io/sarins-lab/azure-devops-agents:latest .\docker

.\scripts\install.ps1 `
  -Organization <your-org> `
  -DockerImage ghcr.io/sarins-lab/azure-devops-agents:latest `
  -AuthToken <your-azure-devops-pat>
```

```bash
docker build -t ghcr.io/sarins-lab/azure-devops-agents:latest ./docker

bash ./scripts/install.sh \
  --organization <your-org> \
  --docker-image ghcr.io/sarins-lab/azure-devops-agents:latest \
  --auth-token <your-azure-devops-pat>
```

On Windows, the installer stores `ADO_MCP_AUTH_TOKEN` as a user environment variable when `-AuthToken` is provided.
On macOS/Linux, the Bash installer stores the token in `~/.ado-mcp/env` with file mode `600` when `--auth-token` is provided.

### Service principal mode

For unattended environments, set these user environment variables before starting the clients:

```powershell
[Environment]::SetEnvironmentVariable("AZURE_CLIENT_ID",     "<id>",     "User")
[Environment]::SetEnvironmentVariable("AZURE_CLIENT_SECRET", "<secret>", "User")
[Environment]::SetEnvironmentVariable("AZURE_TENANT_ID",     "<tenant>", "User")
```

```bash
export AZURE_CLIENT_ID="<id>"
export AZURE_CLIENT_SECRET="<secret>"
export AZURE_TENANT_ID="<tenant>"
```

The launcher detects these values and performs service principal login before starting the MCP server.

## Online Install Commands

Use the online installer when users should not clone or download this repository.
The script runs from GitHub, writes user-level launcher/config/context files, and
does not download the repository archive.

Windows PowerShell:

```powershell
$env:ADO_MCP_ORG = "<your-org>"
irm https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main/scripts/install-online.ps1 | iex
```

Codex only on Windows:

```powershell
$env:ADO_MCP_ORG = "<your-org>"
$env:ADO_MCP_CLIENTS = "Codex"
irm https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main/scripts/install-online.ps1 | iex
```

If a TinyURL is available for PowerShell, point it at:

```text
https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main/scripts/install-online.ps1
```

Then users can run:

```powershell
$env:ADO_MCP_ORG = "<your-org>"
irm https://<your-powershell-tinyurl> | iex
```

Linux/macOS:

```bash
export ADO_MCP_ORG="<your-org>"
curl -fsSL https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main/scripts/install-online.sh | bash
```

Codex only:

```bash
export ADO_MCP_ORG="<your-org>"
export ADO_MCP_CLIENTS="Codex"
curl -fsSL https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main/scripts/install-online.sh | bash
```

For a TinyURL on macOS/Linux, point it at:

```text
https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main/scripts/install-online.sh
```

Then users can run:

```bash
export ADO_MCP_ORG="<your-org>"
curl -fsSL https://<your-bash-tinyurl> | bash
```

Explicit parameter form:

Install for all supported clients:

```powershell
$install = Invoke-RestMethod https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main/scripts/install-online.ps1
& ([scriptblock]::Create($install)) -Organization <your-org>
```

Install for one client:

```powershell
$install = Invoke-RestMethod https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main/scripts/install-online.ps1
& ([scriptblock]::Create($install)) -Organization <your-org> -Clients Codex
& ([scriptblock]::Create($install)) -Organization <your-org> -Clients VSCode
& ([scriptblock]::Create($install)) -Organization <your-org> -Clients Claude
```

One-line form:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$install = Invoke-RestMethod 'https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main/scripts/install-online.ps1'; & ([scriptblock]::Create($install)) -Organization '<your-org>'"
```

The online installer embeds the launcher, Codex context, VS Code context/prompts,
and Claude context. It registers Claude MCP when the Claude CLI is available, but
it does not install the native Claude plugin package because that package
requires a local marketplace directory.

## Repo-Local Install Commands

Use these commands when developing this repository from a local clone.

Install for all supported clients:

Windows:

```powershell
.\scripts\install.ps1 -Organization <your-org>
```

macOS/Linux:

```bash
bash ./scripts/install.sh --organization <your-org>
```

Install for one client:

```powershell
.\scripts\install.ps1 -Organization <your-org> -Clients Claude
.\scripts\install.ps1 -Organization <your-org> -Clients VSCode
.\scripts\install.ps1 -Organization <your-org> -Clients Codex
```

```bash
bash ./scripts/install.sh --organization <your-org> --clients Claude
bash ./scripts/install.sh --organization <your-org> --clients VSCode
bash ./scripts/install.sh --organization <your-org> --clients Codex
```

Force an update when the existing config was created with different organization or Docker settings:

```powershell
.\scripts\install.ps1 -Organization <your-org> -Force
```

```bash
bash ./scripts/install.sh --organization <your-org> --force
```

## Files Written By The Installer

Shared files:

- Windows: `~/.ado-mcp/ado-mcp.ps1`
- macOS/Linux: `~/.ado-mcp/ado-mcp-launcher.sh`
- `~/.ado-mcp/config.json`
- macOS/Linux Docker mode with `--auth-token`: `~/.ado-mcp/env`

Claude Code:

- User-level MCP server named `azure-devops`
- Local Claude marketplace registration for this repo
- Claude plugin install for `azure-devops-agents-claude`
- `~/.claude/CLAUDE.md` merged block

Codex:

- `~/.codex/config.toml`
- `~/.codex/AGENTS.md` merged block

VS Code Copilot:

- Windows: `%APPDATA%\Code\User\mcp.json`
- Windows: `%APPDATA%\Code\User\settings.json`
- macOS: `~/Library/Application Support/Code/User/mcp.json`
- macOS: `~/Library/Application Support/Code/User/settings.json`
- Linux: `${XDG_CONFIG_HOME:-~/.config}/Code/User/mcp.json`
- Linux: `${XDG_CONFIG_HOME:-~/.config}/Code/User/settings.json`
- `~/.ado-mcp/copilot-context.md`
- `~/.ado-mcp/prompts/*.prompt.md`

Claude plugin MCP entrypoint:

- `.claude-plugin/plugin.json` points to root `.mcp.json`.
- `.mcp.json` runs `node scripts/ado-mcp-launcher.mjs`.
- `ado-mcp-launcher.mjs` dispatches to PowerShell on Windows and Bash on macOS/Linux.
- `skills/azure-devops-planning/SKILL.md` carries the Claude plugin planning context.
- The plugin can start the MCP server when Claude loads the plugin. The organization/auth configuration still comes from the installer or environment variables.

## Tooling Contract

The planning prompts and commands must use official Microsoft MCP tool names with the `mcp_ado_*` pattern.

Examples:

- `mcp_ado_wit_get_work_item`
- `mcp_ado_wit_add_child_work_items`
- `mcp_ado_wit_update_work_item`
- `mcp_ado_wiki_get_page_content`

Work item creation uses a create-then-update pattern:

1. Create child items with `mcp_ado_wit_add_child_work_items`.
2. Add fields such as Acceptance Criteria and Story Points with `mcp_ado_wit_update_work_item`.
3. Verify parent links with `mcp_ado_wit_get_work_item`.
4. Repair links with `mcp_ado_wit_work_items_link` if needed.

## Verification

Check PowerShell syntax:

```powershell
$files = @("scripts\install.ps1", "scripts\install-ado-mcp-user.ps1", "scripts\ado-mcp-launcher.ps1")
foreach ($file in $files) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file), [ref]$tokens, [ref]$errors) > $null
  if ($errors.Count -gt 0) { $errors; exit 1 }
}
```

Check Bash and Node syntax:

```bash
bash -n scripts/install.sh scripts/install-ado-mcp-user.sh scripts/ado-mcp-launcher.sh scripts/deploy.sh
node --check scripts/ado-mcp-launcher.mjs
```

Validate the Claude marketplace manifest:

```powershell
claude plugin validate .claude-plugin\marketplace.json
claude plugin tag --dry-run --force .
```

Check Codex MCP registration:

```powershell
codex mcp get azure-devops
```

Check VS Code prompt files:

```powershell
Get-ChildItem ~/.ado-mcp/prompts
```

Expected prompt files:

- `plan-epic.prompt.md`
- `plan-feature.prompt.md`
- `plan-story.prompt.md`

## Troubleshooting

| Symptom                                         | Likely cause                                          | Fix                                                                                |
| ----------------------------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Claude context exists but slash commands do not | Claude CLI was not available during install           | Install Claude Code, then rerun installer or run the manual Claude plugin commands |
| Codex does not see the MCP server               | Client was already running or config was not reloaded | Restart Codex and verify `codex mcp get azure-devops`                              |
| VS Code does not show prompt files              | Prompt directory not loaded yet                       | Restart VS Code and check `chat.promptFilesLocations` in user settings             |
| Docker mode starts but cannot authenticate      | `ADO_MCP_AUTH_TOKEN` missing or invalid               | Set a valid PAT and restart the client                                             |
| Work item creation works but fields are missing | Fields were attempted during create instead of update | Use `mcp_ado_wit_update_work_item` after creation                                  |
| Wiki ADR reading returns metadata only          | Used `mcp_ado_wiki_get_page` alone                    | Call `mcp_ado_wiki_get_page_content` after `mcp_ado_wiki_get_page`                 |

## Release Checklist

Before publishing a release:

1. Run the deployment dry-run:

   ```powershell
   .\scripts\deploy.ps1
   ```

   ```bash
   bash ./scripts/deploy.sh
   ```

2. Install into an isolated test home using `ADO_MCP_HOME`.
3. Verify the three VS Code prompt files are copied.
4. Verify Codex global `AGENTS.md` contains `plan-epic`, `plan-feature`, and `plan-story`.
5. Run a real `/plan-story` against a test Azure DevOps project.
6. Publish only after validation passes:

   ```powershell
   .\scripts\deploy.ps1 -Publish
   ```

   ```bash
   bash ./scripts/deploy.sh --publish
   ```

To include the Docker image in a release:

```powershell
.\scripts\deploy.ps1 `
  -DockerImage ghcr.io/sarins-lab/azure-devops-agents:<version> `
  -BuildDocker `
  -PushDocker `
  -Publish
```

```bash
bash ./scripts/deploy.sh \
  --docker-image ghcr.io/sarins-lab/azure-devops-agents:<version> \
  --build-docker \
  --push-docker \
  --publish
```
