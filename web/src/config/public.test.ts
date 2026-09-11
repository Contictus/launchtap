import { describe, expect, it } from "vitest";
import { publicConfiguration } from "./public";

describe("publicConfiguration", () => {
  it("fails closed for missing values", () => {
    expect(publicConfiguration({})).toMatchObject({ status: "fail-closed", chainId: null });
  });

  it("fails closed for an unknown or wrong-chain deployment", () => {
    const env = {
      NEXT_PUBLIC_DEPLOYMENT_ID: "robinhood-mainnet",
      NEXT_PUBLIC_CHAIN_ID: "46630",
      NEXT_PUBLIC_API_BASE_URL: "https://api.example",
      NEXT_PUBLIC_RPC_URL: "https://rpc.example",
    };
    expect(publicConfiguration(env).status).toBe("fail-closed");
  });

  it("uses the real backend URL for the Anvil fixture instead of a receipt fixture", () => {
    const configuration = publicConfiguration({
      NEXT_PUBLIC_E2E_FIXTURE: "1",
      NEXT_PUBLIC_TASK6_ANVIL_FACTORY: "0x0000000000000000000000000000000000000001",
      NEXT_PUBLIC_TASK6_ANVIL_WETH: "0x0000000000000000000000000000000000000002",
      NEXT_PUBLIC_TASK6_ANVIL_ROUTER: "0x0000000000000000000000000000000000000003",
      NEXT_PUBLIC_TASK6_ANVIL_UNISWAP_FACTORY: "0x0000000000000000000000000000000000000004",
      NEXT_PUBLIC_TASK6_ANVIL_RPC_URL: "http://127.0.0.1:8545",
      NEXT_PUBLIC_TASK6_ANVIL_API_URL: "http://127.0.0.1:18080",
      NEXT_PUBLIC_TASK6_ANVIL_WEB_URL: "http://127.0.0.1:3000",
    });
    expect(configuration.status).toBe("ready");
    expect(configuration.apiBaseUrl).toBe("http://127.0.0.1:18080");
  });

  it("rejects credentials or query material in public endpoints", () => {
    expect(
      publicConfiguration({
        NEXT_PUBLIC_API_BASE_URL: "https://user:pass@example.test",
        NEXT_PUBLIC_RPC_URL: "https://rpc.example?token=secret",
      }).apiBaseUrl,
    ).toBeNull();
    expect(
      publicConfiguration({ NEXT_PUBLIC_API_BASE_URL: "https://api.example?token=secret" })
        .apiBaseUrl,
    ).toBeNull();
  });
});
