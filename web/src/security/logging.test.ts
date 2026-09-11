import { describe, expect, it } from "vitest";
import { redactLogValue, scrubTelemetry } from "./logging";

describe("safe logging", () => {
  it("redacts credentials and signatures recursively", () => {
    expect(
      redactLogValue({
        Authorization: "Bearer access",
        signature: "0x" + "a".repeat(130),
        ok: "value",
      }),
    ).toEqual({ Authorization: "[REDACTED]", signature: "[REDACTED]", ok: "value" });
  });

  it("scrubs error objects without retaining provider payloads", () => {
    const scrubbed = scrubTelemetry(new Error("RPC failed: Bearer very-secret-token"));
    expect(scrubbed).toEqual({ name: "Error", message: "[REDACTED]" });
  });

  it("bounds non-sensitive diagnostic strings", () => {
    expect(redactLogValue("x".repeat(600))).toBe(`${"x".repeat(497)}...`);
  });
});
