import { describe, expect, it } from "vitest";
import { parseTokenAddress, shortAddress } from "./address";

describe("token route addresses", () => {
  it("normalizes a valid EVM address", () => {
    expect(parseTokenAddress("0xABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD")).toBe(
      "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
    );
  });
  it("rejects malformed and non-EVM values", () => {
    expect(parseTokenAddress("0x123")).toBeNull();
    expect(parseTokenAddress("javascript:alert(1)")).toBeNull();
    expect(shortAddress("not-an-address")).toBe("Unavailable");
  });
});
