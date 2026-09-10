import { describe, expect, it } from "vitest";
import { formatBaseUnits, formatDisplayAmount, parseBaseUnits, parseDecimal } from "./amounts";

describe("decimal and bigint amounts", () => {
  it("round trips exact boundaries without floating point", () => {
    expect(parseDecimal("1.000000000000000001")).toBe(1000000000000000001n);
    expect(formatBaseUnits(1000000000000000001n)).toBe("1.000000000000000001");
    expect(formatDisplayAmount(1234567890000000000000n)).toBe("1,234.5678");
  });
  it("rejects malformed and over-precise values", () => {
    expect(() => parseDecimal("1e3")).toThrow();
    expect(() => parseDecimal("1.001", 2)).toThrow();
    expect(() => parseBaseUnits("1.2")).toThrow();
    expect(() => parseDecimal("-1")).toThrow();
  });
});
