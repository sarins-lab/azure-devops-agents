# VS Code Copilot Adapter

`copilot-instructions.md` is copied to `~/.ado-mcp/copilot-context.md` and referenced from VS Code user settings.

Every `*.prompt.md` file in `prompts/` is copied to `~/.ado-mcp/prompts/`, and that folder is added to `chat.promptFilesLocations`.

The shared installer registers the Azure DevOps MCP server in the VS Code user `mcp.json`. On Windows it points to the PowerShell launcher; on macOS/Linux it points to the Bash launcher.
