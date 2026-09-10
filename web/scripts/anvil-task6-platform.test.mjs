import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const webRoot = path.resolve(import.meta.dirname, "..");
const gate = fs.readFileSync(path.join(webRoot, "scripts", "anvil-task6-gate.ps1"), "utf8");
const playwright = fs.readFileSync(path.join(webRoot, "playwright.config.ts"), "utf8");

test("Task 6 gate selects platform commands and paths at runtime", () => {
  assert.match(gate, /\$isWindows\s*=/);
  assert.match(gate, /\$powershellCommand\s*=\s*if \(\$isWindows\)/);
  assert.match(gate, /\$npmCommand\s*=\s*if \(\$isWindows\)/);
  assert.match(gate, /\$foundryExtension\s*=\s*if \(\$isWindows\)/);
  assert.match(gate, /\[IO\.Path\]::PathSeparator/);
  assert.doesNotMatch(gate, /Invoke-Checked\s+"powershell\.exe"/);
  assert.doesNotMatch(gate, /Invoke-Checked\s+"npm\.cmd"/);
  assert.doesNotMatch(gate, /C:\\\\Users\\\$env:USERNAME/);
});

test("Playwright uses installed Chromium on non-Windows", () => {
  assert.match(playwright, /process\.platform\s*===\s*"win32"/);
  assert.match(playwright, /fs\.existsSync\(windowsChromePath\)/);
  assert.match(playwright, /configuredChromePath/);
});
