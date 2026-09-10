import { describe, expect, it } from "vitest";
import { getWalletStatus, switchToSupportedChain } from "./readiness";

describe("wallet readiness", () => {
  it.each([
    [false, undefined, undefined, "provider-loading"],
    [true, undefined, undefined, "disconnected"],
    [true, "0x0000000000000000000000000000000000000001", 1, "wrong-chain"],
    [true, "0x0000000000000000000000000000000000000001", 46630, "ready"],
  ])("returns %s", (providerReady, address, chainId, expected) => {
    expect(
      getWalletStatus({
        providerReady,
        address: address as `0x${string}` | undefined,
        chainId,
        supportedChainId: 46630,
      }),
    ).toBe(expected);
  });
  it("reports switch failures without changing the selected chain", async () => {
    await expect(
      switchToSupportedChain(46630, async () => {
        throw new Error("rejected");
      }),
    ).resolves.toEqual({ ok: false, error: "switch-failed" });
    await expect(switchToSupportedChain(46630, undefined)).resolves.toEqual({
      ok: false,
      error: "switch-failed",
    });
  });
});
