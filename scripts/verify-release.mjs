import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const windows = process.platform === "win32";
const npm = windows ? "npm.cmd" : "npm";
const task = ["run", "github.com/go-task/task/v3/cmd/task@v3.53.1", "verify"];

function required(command) {
  const probe = spawnSync(windows ? "where.exe" : "which", [command], { stdio: "ignore" });
  if (probe.status !== 0) throw new Error(`Required command is missing: ${command}`);
}

function run(command, args, cwd, env = {}) {
  console.log(`\n> ${command} ${args.join(" ")}`);
  const result = spawnSync(command, args, { cwd, env: { ...process.env, ...env }, stdio: "inherit", shell: false });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed with exit code ${result.status}`);
}

try {
  for (const command of ["forge", "go", npm]) required(command);
  if (!fs.existsSync(path.join(root, "contracts", "scripts", "check.ps1"))) throw new Error("Contract gate script is missing");
  if (!fs.existsSync(path.join(root, "backend", "Taskfile.yml"))) throw new Error("Backend Taskfile is missing");
  if (!fs.existsSync(path.join(root, "web", "package-lock.json"))) throw new Error("Web lockfile is missing");

  const shell = windows ? "powershell.exe" : "pwsh";
  required(shell);
  run(shell, ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "contracts/scripts/check.ps1", "all"], root);
  run("go", task, path.join(root, "backend"));
  run(npm, ["ci"], path.join(root, "web"));
  run(npm, ["run", "web-api-diff"], path.join(root, "web"));
  run(npm, ["run", "web-contracts-diff"], path.join(root, "web"));
  run(npm, ["run", "format:check"], path.join(root, "web"));
  run(npm, ["run", "lint"], path.join(root, "web"));
  run(npm, ["run", "typecheck"], path.join(root, "web"));
  run(npm, ["test"], path.join(root, "web"));
  run(npm, ["run", "build"], path.join(root, "web"));
  run(npm, ["run", "verify:bundle"], path.join(root, "web"));
  run(npm, ["run", "test:e2e"], path.join(root, "web"));
  // The Anvil gate is mandatory: it starts and checks Anvil, API, indexer, and PostgreSQL itself.
  run(npm, ["run", "test:anvil"], path.join(root, "web"));
  console.log("\nRelease verification passed: contracts, backend, web, browser, and Anvil gates completed.");
} catch (error) {
  console.error(`\nRelease verification failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
}
