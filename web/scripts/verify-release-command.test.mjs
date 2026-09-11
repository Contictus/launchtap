import { describe, expect, it } from "vitest";

import {
  browserProvisioningMode,
  powerShellPrerequisiteMessage,
  releaseCommandTimeoutMs,
  run,
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

  it("uses a bounded default and accepts a positive override", () => {
    expect(releaseCommandTimeoutMs({})).toBe(10 * 60 * 1000);
    expect(releaseCommandTimeoutMs({ RELEASE_COMMAND_TIMEOUT_MS: "2500" })).toBe(2500);
    expect(releaseCommandTimeoutMs({ RELEASE_COMMAND_TIMEOUT_MS: "0" })).toBe(10 * 60 * 1000);
  });

  it("requires pre-provisioned browsers on Unix and preserves Windows fallback", () => {
    expect(
      browserProvisioningMode({ PLAYWRIGHT_EXECUTABLE_PATH: "/usr/bin/google-chrome" }, "linux"),
    ).toBe("system");
    expect(browserProvisioningMode({}, "linux")).toBe("missing");
    expect(browserProvisioningMode({}, "win32")).toBe("windows-fallback");
  });

  it("terminates a child that exceeds the release command timeout", () => {
    expect(() =>
      run(
        process.execPath,
        ["-e", "setTimeout(() => {}, 60_000)"],
        process.cwd(),
        {},
        {
          timeoutMs: 50,
        },
      ),
    ).toThrow(/timed out after 50ms/);
  });
});
