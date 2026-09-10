import { describe, expect, it } from "vitest";
import {
  createTransactionState,
  transitionTransaction,
  type TransactionReadiness,
} from "./transactions";

const ready: TransactionReadiness = {
  providerReady: true,
  configurationReady: true,
  walletConnected: true,
  chainSupported: true,
  selectedAccountVerified: true,
  linkedWalletState: "linked",
};

describe("transaction state machine", () => {
  it("keeps signature, receipt, indexing, and finality distinct", () => {
    let state = createTransactionState("disconnected");
    expect(() => transitionTransaction(state, { type: "validate" })).toThrow("readiness");
    state = transitionTransaction(state, { type: "validate" }, ready);
    for (const type of [
      "simulate",
      "await-signature",
      "submitted",
      "mined",
      "indexing",
      "indexed",
      "safe",
      "finalized",
    ] as const)
      state = transitionTransaction(state, { type, hash: "0x123" as `0x${string}` }, ready);
    expect(state.status).toBe("finalized");
  });

  it("cannot progress from disconnected, wrong-chain, provider-loading, or disabled config", () => {
    for (const status of ["disconnected", "wrong-chain", "provider-loading"] as const)
      expect(() =>
        transitionTransaction(createTransactionState(status), { type: "validate" }),
      ).toThrow("readiness");
    expect(() =>
      transitionTransaction(
        createTransactionState("disconnected"),
        { type: "validate" },
        { ...ready, configurationReady: false },
      ),
    ).toThrow("readiness");
    expect(() =>
      transitionTransaction(
        createTransactionState("disconnected"),
        { type: "validate" },
        { ...ready, selectedAccountVerified: false },
      ),
    ).toThrow("readiness");
    for (const linkedWalletState of ["connected-unlinked", "linked-mismatch"] as const)
      expect(() =>
        transitionTransaction(
          createTransactionState("disconnected"),
          { type: "validate" },
          { ...ready, linkedWalletState },
        ),
      ).toThrow("readiness");
  });

  it.each(["rejected-signature", "rpc-failure", "reverted"] as const)(
    "supports %s as a terminal failure",
    (failure) => {
      let state = createTransactionState("disconnected");
      state = transitionTransaction(state, { type: "validate" }, ready);
      state = transitionTransaction(state, { type: "simulate" }, ready);
      state = transitionTransaction(state, { type: "await-signature" }, ready);
      if (failure === "reverted")
        state = transitionTransaction(state, { type: "submitted" }, ready);
      state = transitionTransaction(state, { type: failure });
      expect(state.status).toBe(failure);
    },
  );

  it("requires indexed state before safe and finalized", () => {
    let state = createTransactionState("disconnected");
    for (const type of ["validate", "simulate", "await-signature", "submitted", "mined"] as const)
      state = transitionTransaction(state, { type }, ready);
    expect(() => transitionTransaction(state, { type: "safe" })).toThrow();
    state = transitionTransaction(state, { type: "indexing" });
    expect(() => transitionTransaction(state, { type: "finalized" })).toThrow();
    state = transitionTransaction(state, { type: "indexed" });
    state = transitionTransaction(state, { type: "safe" });
    state = transitionTransaction(state, { type: "finalized" });
    expect(state.status).toBe("finalized");
  });
});
