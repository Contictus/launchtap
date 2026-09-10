import type { components } from "./generated";

export type Snapshot = components["schemas"]["SnapshotDTO"];
export type CursorPage<T> = { items: T[] | null; next_cursor?: string; snapshot: Snapshot };
export type TokenList = components["schemas"]["TokenDTO"];
export type ApiEvent =
  | { event: "launch"; data: components["schemas"]["LaunchEvent"] }
  | { event: "reorg"; data: components["schemas"]["ReorgEvent"] }
  | { event: "token"; data: components["schemas"]["TokenEvent"] };

export function snapshotIdentity(snapshot: Snapshot | null | undefined) {
  return snapshot
    ? `${snapshot.chain_id}:${snapshot.as_of_block}:${snapshot.as_of_block_hash}:${snapshot.finality}`
    : null;
}

export const queryKeys = {
  all: (chainId: number | null, deploymentId: string | null) =>
    ["launchpad", chainId, deploymentId] as const,
  tokens: (
    chainId: number | null,
    deploymentId: string | null,
    filters: Record<string, unknown> = {},
    snapshot?: Snapshot,
  ) =>
    [
      ...queryKeys.all(chainId, deploymentId),
      "tokens",
      filters,
      snapshotIdentity(snapshot),
    ] as const,
  token: (chainId: number | null, deploymentId: string | null, address: string) =>
    [...queryKeys.all(chainId, deploymentId), "token", address.toLowerCase()] as const,
  trades: (
    chainId: number | null,
    deploymentId: string | null,
    address: string,
    cursor?: string,
    snapshot?: Snapshot,
  ) =>
    [
      ...queryKeys.token(chainId, deploymentId, address),
      "trades",
      cursor ?? null,
      snapshotIdentity(snapshot),
    ] as const,
  holders: (
    chainId: number | null,
    deploymentId: string | null,
    address: string,
    cursor?: string,
    snapshot?: Snapshot,
  ) =>
    [
      ...queryKeys.token(chainId, deploymentId, address),
      "holders",
      cursor ?? null,
      snapshotIdentity(snapshot),
    ] as const,
  candles: (
    chainId: number | null,
    deploymentId: string | null,
    address: string,
    filters: Record<string, unknown> = {},
    snapshot?: Snapshot,
  ) =>
    [
      ...queryKeys.token(chainId, deploymentId, address),
      "candles",
      filters,
      snapshotIdentity(snapshot),
    ] as const,
  protocol: (chainId: number | null, deploymentId: string | null) =>
    [...queryKeys.all(chainId, deploymentId), "protocol"] as const,
  protocolDaily: (
    chainId: number | null,
    deploymentId: string | null,
    filters: Record<string, unknown> = {},
  ) => [...queryKeys.protocol(chainId, deploymentId), "daily", filters] as const,
};
