import { describe, expect, it } from "vitest";
import { createTransactionState, transitionTransaction } from "./transactions";

describe("transaction state machine", () => {
  it("keeps signature, receipt, indexing, and finality distinct", () => {
    let state = createTransactionState("disconnected");
    for (const type of [
      "validate",
      "simulate",
      "await-signature",
      "submitted",
      "mined",
      "indexing",
      "indexed",
      "safe",
      "finalized",
    ] as const)
      state = transitionTransaction(state, { type, hash: "0x123" as `0x${string}` });
    expect(state.status).toBe("finalized");
  });
  it.each(["rejected-signature", "rpc-failure", "reverted"] as const)(
    "supports %s as a terminal failure",
    (failure) => {
      let state = createTransactionState("disconnected");
      state = transitionTransaction(state, { type: "validate" });
      state = transitionTransaction(state, { type: "simulate" });
      state = transitionTransaction(state, { type: "await-signature" });
      if (failure === "reverted") state = transitionTransaction(state, { type: "submitted" });
      state = transitionTransaction(state, { type: failure });
      expect(state.status).toBe(failure);
    },
  );
});
