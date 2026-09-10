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
});
