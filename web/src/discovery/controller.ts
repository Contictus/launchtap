import type { TokenListQuery, TokenListResponse } from "@/api/client";
import { ApiProblem } from "@/api/problems";
import { snapshotIdentity, type Snapshot } from "@/api/types";
import type { TokenListQueryState } from "./query-state";
import { tokenListFilters } from "./query-state";

export type DiscoveryPageFetcher = (
  query: TokenListQuery,
  signal?: AbortSignal,
) => Promise<TokenListResponse>;

export type AppendRecoveryResult = {
  pages: TokenListResponse[];
  reset: boolean;
};

export type TokenDiscoveryPageOptions = {
  fetchPage: DiscoveryPageFetcher;
  state: TokenListQueryState;
  cursor?: string;
  existingPages: TokenListResponse[];
  signal?: AbortSignal;
};

/**
 * Append one cursor page without ever mixing snapshots. Cursor invalidation and a changed
 * snapshot both recover through exactly one page-one request; the caller owns UI state.
 */
export async function appendTokenListPage(
  options: TokenDiscoveryPageOptions & { cursor: string },
): Promise<AppendRecoveryResult> {
  const { fetchPage, state, cursor, existingPages, signal } = options;
  let reset = false;
  let response: TokenListResponse;
  try {
    response = await fetchPage({ ...tokenListFilters(state), cursor }, signal);
  } catch (cause) {
    if (
      !(cause instanceof ApiProblem) ||
      (cause.code !== "cursor_invalidated" && cause.code !== "invalid_cursor")
    ) {
      throw cause;
    }
    reset = true;
    response = await fetchPage({ ...tokenListFilters(state), cursor: undefined }, signal);
  }
  const currentSnapshot: Snapshot | undefined = existingPages[0]?.snapshot;
  if (
    !reset &&
    currentSnapshot &&
    snapshotIdentity(currentSnapshot) !== snapshotIdentity(response.snapshot)
  ) {
    reset = true;
    return {
      pages: [await fetchPage({ ...tokenListFilters(state), cursor: undefined }, signal)],
      reset: true,
    };
  }
  return { pages: reset ? [response] : [...existingPages, response], reset };
}

/** The production page coordinator used by TokenDiscovery for initial and cursor loads. */
export async function loadTokenDiscoveryPage(
  options: TokenDiscoveryPageOptions,
): Promise<AppendRecoveryResult> {
  if (options.cursor) return appendTokenListPage({ ...options, cursor: options.cursor });
  const response = await options.fetchPage(
    { ...tokenListFilters(options.state), cursor: undefined },
    options.signal,
  );
  return { pages: [response], reset: false };
}
