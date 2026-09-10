import { describe, expect, it } from "vitest";
import { redactLogValue } from "./logging";

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
});
