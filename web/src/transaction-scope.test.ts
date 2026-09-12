import { describe, expect, it } from "vitest";
import { createScopeBoundCommitter, transactionStateForScope } from "./transaction-scope";
import {
  readPersistedTransaction,
  writePersistedTransaction,
  type TransactionStorageContext,
} from "./transaction-storage";
import type { TransactionState } from "./transactions";

function memoryStorage() {
  const values = new Map<string, string>();
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
  };
}

const oldContext: TransactionStorageContext = {
  chainId: 46630,
  account: "0x1111111111111111111111111111111111111111",
  tokenAddress: "0x2222222222222222222222222222222222222222",
  action: "trade",
};
const newContext: TransactionStorageContext = {
  ...oldContext,
  account: "0x3333333333333333333333333333333333333333",
};
const oldHash = `0x${"a".repeat(64)}` as `0x${string}`;
const newHash = `0x${"b".repeat(64)}` as `0x${string}`;
const scopeFor = (context: TransactionStorageContext) =>
  `${context.chainId}:${context.account}:${context.tokenAddress}:${context.action}`;

describe("transaction scope isolation", () => {
  it("ignores an old in-flight refresh after restoring another scope", async () => {
    const storage = memoryStorage();
    const oldScope = scopeFor(oldContext);
    const newScope = scopeFor(newContext);
    let activeScope = oldScope;
    let snapshot = {
      scope: oldScope,
      state: { status: "safe", hash: oldHash } as TransactionState,
    };
    const committedScopes: string[] = [];
    const observerRequests: Array<{ scope: string; hash: string }> = [];
    let resolveRefresh!: (state: TransactionState) => void;
    const oldRefresh = new Promise<TransactionState>((resolve) => {
      resolveRefresh = resolve;
    });
    const commitOldRefresh = createScopeBoundCommitter<TransactionState>(
      oldScope,
      () => activeScope,
      (state) => {
        snapshot = { scope: oldScope, state };
        committedScopes.push(oldScope);
        if (state.hash)
          writePersistedTransaction(
            oldContext,
            { hash: state.hash, status: state.status },
            storage,
            1_000,
          );
      },
    );
    const oldRequest = oldRefresh.then((state) => commitOldRefresh(state));

    writePersistedTransaction(newContext, { hash: newHash, status: "safe" }, storage, 1_001);
    activeScope = newScope;
    const restored = readPersistedTransaction(newContext, storage, 1_002);
    snapshot = {
      scope: newScope,
      state: restored
        ? { status: restored.status, hash: restored.hash }
        : { status: "disconnected" },
    };
    const restoredState = transactionStateForScope(snapshot, newScope);
    if (restoredState.hash) observerRequests.push({ scope: newScope, hash: restoredState.hash });

    resolveRefresh({ status: "finalized", hash: oldHash });
    expect(await oldRequest).toBe(false);

    expect(transactionStateForScope(snapshot, newScope)).toEqual(restoredState);
    expect(transactionStateForScope(snapshot, newScope).hash).toBe(newHash);
    expect(committedScopes).toEqual([]);
    expect(observerRequests).toEqual([{ scope: newScope, hash: newHash }]);
    expect(readPersistedTransaction(newContext, storage, 1_003)?.hash).toBe(newHash);
    expect(readPersistedTransaction(oldContext, storage, 1_003)).toBeNull();
  });
});
