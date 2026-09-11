import { describe, expect, it } from "vitest";
import { validateReleaseEnvironment } from "./validate-release.mjs";

const reviewed = [
  {
    deploymentId: "production",
    chainId: 46630,
    enabled: true,
    factory: "0x0000000000000000000000000000000000000001",
    weth: "0x0000000000000000000000000000000000000002",
    uniswapV2Factory: "0x0000000000000000000000000000000000000003",
    uniswapV2Router02: "0x0000000000000000000000000000000000000004",
  },
];
const valid = {
  NEXT_PUBLIC_PRIVY_APP_ID: "cl_live_1234567890",
  NEXT_PUBLIC_DEPLOYMENT_ID: "production",
  NEXT_PUBLIC_CHAIN_ID: "46630",
  NEXT_PUBLIC_API_BASE_URL: "https://api.example",
  NEXT_PUBLIC_RPC_URL: "https://rpc.example",
  NEXT_PUBLIC_WEB_ORIGIN: "https://launchpad.example",
};

describe("release target validation", () => {
  it("fails closed for an unknown target and missing values", () => {
    expect(validateReleaseEnvironment({}, "staging")).toContain(
      "release mode must be production or anvil",
    );
    expect(validateReleaseEnvironment({}, "production")).toContain(
      "NEXT_PUBLIC_WEB_ORIGIN is required",
    );
  });

  it("accepts only a complete reviewed production configuration", () => {
    expect(validateReleaseEnvironment(valid, "production", reviewed)).toEqual([]);
    expect(
      validateReleaseEnvironment(
        { ...valid, NEXT_PUBLIC_DEPLOYMENT_ID: "unknown" },
        "production",
        reviewed,
      ),
    ).toContain("deployment ID and chain ID are not in the reviewed manifest");
    expect(
      validateReleaseEnvironment(
        { ...valid, NEXT_PUBLIC_E2E_FIXTURE: "1" },
        "production",
        reviewed,
      ),
    ).toContain("E2E fixture is not deployable");
  });

  it("requires explicit fixture mode for deterministic Anvil", () => {
    expect(validateReleaseEnvironment({ ...valid }, "anvil", reviewed)).toContain(
      "Anvil gate requires NEXT_PUBLIC_E2E_FIXTURE=1",
    );
    expect(
      validateReleaseEnvironment({ ...valid, NEXT_PUBLIC_E2E_FIXTURE: "1" }, "anvil", reviewed),
    ).toEqual([]);
  });
});
