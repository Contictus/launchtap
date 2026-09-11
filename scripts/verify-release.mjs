import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const root = path.resolve(import.meta.dirname, "..");
const task = ["run", "github.com/go-task/task/v3/cmd/task@v3.53.1", "verify"];

export function selectPowerShellCommand(platform = process.platform) {
  // PowerShell 7 is required by the contract scripts on every host. Windows
  // PowerShell 5.1 is not a compatible fallback.
  return "pwsh";
}

export function powerShellPrerequisiteMessage(platform = process.platform) {
  if (platform === "win32")
    return "PowerShell 7 (pwsh) is required on Windows to run the contract release gate; install PowerShell 7 and ensure pwsh is on PATH.";
  return "Required command is missing: pwsh";
}

export function selectedTarget(argv = process.argv, env = process.env) {
  const argument = argv.find((value) => value.startsWith("--target="));
  const target = argument
    ? argument.slice("--target=".length)
    : env.RELEASE_TARGET;
  if (!target)
    throw new Error(
      "Release target is required. Use --target=production or --target=anvil.",
    );
  if (target !== "production" && target !== "anvil")
    throw new Error(
      `Unknown release target: ${target}. Use production or anvil.`,
    );
  return target;
}

function required(command, platform = process.platform) {
  const probe = spawnSync(
    platform === "win32" ? "where.exe" : "which",
    [command],
    {
      stdio: "ignore",
    },
  );
  if (probe.status !== 0)
    throw new Error(
      command === "pwsh"
        ? powerShellPrerequisiteMessage(platform)
        : `Required command is missing: ${command}`,
    );
}

function run(command, args, cwd, env = {}) {
  console.log(`\n> ${command} ${args.join(" ")}`);
  const result = spawnSync(command, args, {
    cwd,
    env: { ...process.env, ...env },
    stdio: "inherit",
    shell: false,
  });
  if (result.error) throw result.error;
  if (result.status !== 0)
    throw new Error(`${command} failed with exit code ${result.status}`);
}

export function runReleaseVerification(
  argv = process.argv,
  env = process.env,
  platform = process.platform,
) {
  const windows = platform === "win32";
  const npm = windows ? "npm.cmd" : "npm";
  const target = selectedTarget(argv, env);
  const shell = selectPowerShellCommand(platform);
  required(shell, platform);
  for (const command of ["forge", "go", npm]) required(command, platform);
  if (!fs.existsSync(path.join(root, "contracts", "scripts", "check.ps1")))
    throw new Error("Contract gate script is missing");
  if (!fs.existsSync(path.join(root, "backend", "Taskfile.yml")))
    throw new Error("Backend Taskfile is missing");
  if (!fs.existsSync(path.join(root, "web", "package-lock.json")))
    throw new Error("Web lockfile is missing");

  run(
    shell,
    [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      "contracts/scripts/check.ps1",
      "all",
    ],
    root,
  );
  run("go", task, path.join(root, "backend"));
  run(npm, ["ci"], path.join(root, "web"));
  // The selected target is part of the release gate. Production cannot proceed
  // without real reviewed deployment, Privy, API, RPC, and public-origin values.
  run(
    npm,
    [
      "run",
      target === "production" ? "verify:release" : "verify:anvil-config",
      "--",
      target === "production" ? "--production" : "--anvil",
    ],
    path.join(root, "web"),
    target === "anvil" ? { NEXT_PUBLIC_E2E_FIXTURE: "1" } : {},
  );
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
  console.log(
    `\nRelease verification passed for ${target}: contracts, backend, web, browser, and Anvil gates completed.`,
  );
}

const isMain =
  process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url;
if (isMain) {
  try {
    runReleaseVerification();
  } catch (error) {
    console.error(
      `\nRelease verification failed: ${error instanceof Error ? error.message : String(error)}`,
    );
    process.exit(1);
  }
}
