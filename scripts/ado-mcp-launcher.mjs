import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = process.env.CLAUDE_PLUGIN_ROOT || dirname(here);
const scriptsDir = join(root, "scripts");
const isWindows = process.platform === "win32";

const command = isWindows ? "powershell.exe" : "bash";
const args = isWindows
  ? [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      join(scriptsDir, "ado-mcp-launcher.ps1"),
    ]
  : [join(scriptsDir, "ado-mcp-launcher.sh")];

const child = spawn(command, args, {
  stdio: "inherit",
  env: process.env,
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 1);
});

child.on("error", (error) => {
  console.error(`Failed to start ${command}: ${error.message}`);
  process.exit(1);
});
