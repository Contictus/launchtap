import { describe, expect, it } from "vitest";
import {
  getLinkedWalletAddresses,
  getLinkedWalletState,
  getWalletStatus,
  switchToSupportedChain,
} from "./readiness";

describe("wallet readiness", () => {
  it.each([
    [false, false, undefined, undefined, "configuration-unavailable"],
    [true, false, undefined, undefined, "provider-loading"],
    [false, true, undefined, undefined, "configuration-unavailable"],
    [true, true, undefined, undefined, "disconnected"],
    [true, true, "0x0000000000000000000000000000000000000001", 1, "wrong-chain"],
    [true, true, "0x0000000000000000000000000000000000000001", 46630, "ready"],
  ])("returns %s", (configurationReady, providerReady, address, chainId, expected) => {
    expect(
      getWalletStatus({
        configurationReady,
        providerReady,
        address: address as `0x${string}` | undefined,
        chainId,
        supportedChainId: 46630,
      }),
    ).toBe(expected);
  });

  it("distinguishes connected-unlinked, linked, and linked mismatch", () => {
    const linkedWallets = getLinkedWalletAddresses({
      linkedAccounts: [{ type: "wallet", address: "0x0000000000000000000000000000000000000001" }],
    });
    expect(
      getLinkedWalletState({
        configurationReady: true,
        providerReady: true,
        authenticated: false,
        address: linkedWallets[0]?.address,
        linkedWallets,
      }),
    ).toBe("connected-unlinked");
    expect(
      getLinkedWalletState({
        configurationReady: true,
        providerReady: true,
        authenticated: true,
        address: linkedWallets[0]?.address,
        linkedWallets,
      }),
    ).toBe("linked");
    expect(
      getLinkedWalletState({
        configurationReady: true,
        providerReady: true,
        authenticated: true,
        address: "0x0000000000000000000000000000000000000002",
        linkedWallets,
      }),
    ).toBe("linked-mismatch");
    expect(
      getLinkedWalletState({
        configurationReady: false,
        providerReady: true,
        authenticated: true,
        linkedWallets,
      }),
    ).toBe("configuration-unavailable");
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
