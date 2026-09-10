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
export type TransactionReadiness = {
  providerReady: boolean;
  configurationReady: boolean;
  walletConnected: boolean;
  chainSupported: boolean;
  selectedAccountVerified: boolean;
  linkedWalletState:
    | "configuration-unavailable"
    | "provider-loading"
    | "unlinked"
    | "connected-unlinked"
    | "linked"
    | "linked-mismatch";
};
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
  "provider-loading": ["disconnected", "wrong-chain"],
  disconnected: ["provider-loading", "validating"],
  "wrong-chain": ["provider-loading", "disconnected", "validating"],
  validating: ["simulating", "disconnected", "wrong-chain", "rpc-failure"],
  simulating: ["awaiting-signature", "rpc-failure", "reverted"],
  "awaiting-signature": ["rejected-signature", "submitted", "rpc-failure"],
  "rejected-signature": ["validating", "disconnected"],
  submitted: ["mined", "reverted", "rpc-failure"],
  "rpc-failure": ["validating", "disconnected", "wrong-chain"],
  reverted: ["validating", "disconnected"],
  mined: ["indexing"],
  indexing: ["indexed", "rpc-failure"],
  indexed: ["safe"],
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
  readiness?: TransactionReadiness,
): TransactionState {
  const next: TransactionStatus =
    event.type === "validate"
      ? "validating"
      : event.type === "simulate"
        ? "simulating"
        : event.type === "await-signature"
          ? "awaiting-signature"
          : event.type;
  if (
    (event.type === "validate" ||
      event.type === "simulate" ||
      event.type === "await-signature" ||
      event.type === "submitted") &&
    !isTransactionReady(readiness)
  )
    throw new Error("Transaction requires verified wallet and configuration readiness");
  if (!transitions[state.status].includes(next))
    throw new Error(`Invalid transaction transition: ${state.status} -> ${next}`);
  return { status: next, hash: event.hash ?? state.hash, error: event.error };
}

export function isTransactionReady(readiness: TransactionReadiness | undefined): boolean {
  return Boolean(
    readiness?.providerReady &&
    readiness.configurationReady &&
    readiness.walletConnected &&
    readiness.chainSupported &&
    readiness.selectedAccountVerified &&
    readiness.linkedWalletState === "linked",
  );
}

export function canTransitionTransaction(from: TransactionStatus, to: TransactionStatus) {
  return transitions[from].includes(to);
}
