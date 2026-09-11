import { describe, expect, it } from "vitest";

import {
  powerShellPrerequisiteMessage,
  selectPowerShellCommand,
} from "../../scripts/verify-release.mjs";

describe("root release gate PowerShell selection", () => {
  it("uses PowerShell 7 on Windows and Unix hosts", () => {
    expect(selectPowerShellCommand("win32")).toBe("pwsh");
    expect(selectPowerShellCommand("linux")).toBe("pwsh");
    expect(selectPowerShellCommand("darwin")).toBe("pwsh");
  });

  it("reports the Windows prerequisite instead of falling back to Windows PowerShell", () => {
    expect(powerShellPrerequisiteMessage("win32")).toContain(
      "PowerShell 7 (pwsh) is required on Windows",
    );
    expect(powerShellPrerequisiteMessage("win32")).not.toContain("powershell.exe");
  });
});
