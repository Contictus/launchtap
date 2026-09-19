import { describe, expect, it } from "vitest";
import { walletConnectorLabel } from "./connection";

describe("walletConnectorLabel", () => {
  it("uses a clear label for a generic injected provider", () => {
    expect(walletConnectorLabel("Injected")).toBe("Browser wallet");
    expect(walletConnectorLabel(" ")).toBe("Browser wallet");
  });

  it("keeps a wallet provider's own name", () => {
    expect(walletConnectorLabel("WalletConnect")).toBe("WalletConnect");
  });
});
