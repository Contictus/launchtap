import { createTransactionState, type TransactionState } from "./transactions";

export type ScopedTransactionSnapshot = {
  scope: string;
  state: TransactionState;
};

export function transactionStateForScope(
  snapshot: ScopedTransactionSnapshot,
  scope: string,
): TransactionState {
  return snapshot.scope === scope ? snapshot.state : createTransactionState("disconnected");
}

export function createScopeBoundCommitter<T>(
  expectedScope: string,
  currentScope: () => string,
  commit: (value: T) => void,
): (value: T) => boolean {
  return (value) => {
    if (currentScope() !== expectedScope) return false;
    commit(value);
    return true;
  };
}
