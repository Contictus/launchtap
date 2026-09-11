import { describe, expect, it } from "vitest";
import { isTokenEventForAddress } from "./sse-scope";

const base = { chain_id: 1, deployment_id: "local" };
describe("token SSE scope", () => {
  it("accepts only the displayed token", () => {
    expect(
      isTokenEventForAddress(
        { event: "token", data: { ...base, token: "0x0000000000000000000000000000000000000001" } },
        "0x0000000000000000000000000000000000000001",
      ),
    ).toBe(true);
    expect(
      isTokenEventForAddress(
        { event: "token", data: { ...base, token: "0x0000000000000000000000000000000000000002" } },
        "0x0000000000000000000000000000000000000001",
      ),
    ).toBe(false);
  });
  it("does not broaden a global reorg event to a token refresh", () => {
    expect(
      isTokenEventForAddress(
        { event: "reorg", data: { ...base, common_ancestor: 5 } },
        "0x0000000000000000000000000000000000000001",
      ),
    ).toBe(false);
  });
});
