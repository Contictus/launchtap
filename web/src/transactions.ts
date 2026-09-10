export type TransactionStatus =
  | "disconnected"
  | "provider-loading"
  | "wrong-chain"
  | "validating"
  | "simulating"
  | "awaiting-signature"
  | "rejected-signature"
  | "submitted"
  | "rpc-failure"
  | "reverted"
  | "mined"
  | "indexing"
  | "indexed"
  | "safe"
  | "finalized";
export type TransactionState = { status: TransactionStatus; hash?: `0x${string}`; error?: string };
export type TransactionEvent = {
  type:
    | "provider-loading"
    | "disconnected"
    | "wrong-chain"
    | "validate"
    | "simulate"
    | "await-signature"
    | "rejected-signature"
    | "submitted"
    | "rpc-failure"
    | "reverted"
    | "mined"
    | "indexing"
    | "indexed"
    | "safe"
    | "finalized";
  hash?: `0x${string}`;
  error?: string;
};

const transitions: Record<TransactionStatus, readonly TransactionStatus[]> = {
  "provider-loading": ["disconnected", "wrong-chain", "validating"],
  disconnected: ["provider-loading", "validating"],
  "wrong-chain": ["provider-loading", "disconnected", "validating"],
  validating: ["simulating", "disconnected", "wrong-chain", "rpc-failure"],
  simulating: ["awaiting-signature", "rpc-failure", "reverted"],
  "awaiting-signature": ["rejected-signature", "submitted", "rpc-failure"],
  "rejected-signature": ["validating", "disconnected"],
  submitted: ["mined", "reverted", "rpc-failure"],
  "rpc-failure": ["validating", "disconnected", "wrong-chain"],
  reverted: ["validating", "disconnected"],
  mined: ["indexing", "safe", "finalized"],
  indexing: ["indexed", "safe", "finalized", "rpc-failure"],
  indexed: ["safe", "finalized"],
  safe: ["finalized"],
  finalized: [],
};

export function createTransactionState(
  status: TransactionStatus = "disconnected",
): TransactionState {
  return { status };
}

export function transitionTransaction(
  state: TransactionState,
  event: TransactionEvent,
): TransactionState {
  const next: TransactionStatus =
    event.type === "validate"
      ? "validating"
      : event.type === "simulate"
        ? "simulating"
        : event.type === "await-signature"
          ? "awaiting-signature"
          : event.type;
  if (!transitions[state.status].includes(next))
    throw new Error(`Invalid transaction transition: ${state.status} -> ${next}`);
  return { status: next, hash: event.hash ?? state.hash, error: event.error };
}

export function canTransitionTransaction(from: TransactionStatus, to: TransactionStatus) {
  return transitions[from].includes(to);
}
