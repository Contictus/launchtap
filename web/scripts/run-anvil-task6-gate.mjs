import { spawnSync } from "node:child_process";

const shell = process.platform === "win32" ? "powershell.exe" : "pwsh";
const args = [
  "-NoProfile",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  "scripts/anvil-task6-gate.ps1",
  ...process.argv.slice(2),
];
const result = spawnSync(shell, args, { stdio: "inherit" });
if (result.error) {
  console.error(`Task 6 Anvil gate requires ${shell}: ${result.error.message}`);
  process.exit(1);
}
process.exit(result.status ?? 1);
