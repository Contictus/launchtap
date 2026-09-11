import { describe, expect, it } from "vitest";
import { scanBundleText, validatePerformanceBudgetMatrix } from "./check-budgets.mjs";

describe("release bundle and performance budgets", () => {
  it("requires every profile and core route, including populated token detail", () => {
    expect(validatePerformanceBudgetMatrix()).toEqual([]);
    expect(validatePerformanceBudgetMatrix({ version: 1, routes: ["/"], profiles: {} })).toEqual(
      expect.arrayContaining([
        "performance budget is missing mobile profile",
        "performance budget is missing the populated token fixture route",
      ]),
    );
  });

  it("detects private keys, known Anvil wallets, and unreviewed addresses", () => {
    const key = `0x${"ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"}`;
    const findings = scanBundleText(
      `${key} 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 0x1111111111111111111111111111111111111111`,
      "fixture.js",
    );
    expect(findings.some((value) => value.includes("private-key"))).toBe(true);
    expect(findings.some((value) => value.includes("unreviewed address"))).toBe(true);
  });

  it("allows reviewed deployment addresses and contiguous bytecode blobs", () => {
    const reviewed = "0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73";
    const bytecode = `0x${"ab".repeat(80)}`;
    expect(scanBundleText(`${reviewed} ${bytecode}`, "generated.js")).toEqual([]);
  });
});
