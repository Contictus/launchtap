import { ApiProblem } from "@/api/problems";
import { snapshotIdentity, type Snapshot } from "@/api/types";
import type { CandleResponse, HoldersResponse, TradesResponse } from "@/api/client";

export type TokenCollection = TradesResponse | HoldersResponse;
export type TokenCollectionFetcher = (
  cursor?: string,
  signal?: AbortSignal,
) => Promise<TokenCollection>;

/** Keep a tab's pages on one snapshot; a cursor error or snapshot drift starts page one again. */
export async function appendTokenCollectionPage(
  fetchPage: TokenCollectionFetcher,
  pages: TokenCollection[],
  cursor: string,
  signal?: AbortSignal,
) {
  let response: TokenCollection;
  let reset = false;
  try {
    response = await fetchPage(cursor, signal);
  } catch (cause) {
    if (
      !(cause instanceof ApiProblem) ||
      !["cursor_invalidated", "invalid_cursor"].includes(cause.code)
    )
      throw cause;
    response = await fetchPage(undefined, signal);
    reset = true;
  }
  const currentSnapshot: Snapshot | undefined = pages[0]?.snapshot;
  if (
    !reset &&
    currentSnapshot &&
    snapshotIdentity(currentSnapshot) !== snapshotIdentity(response.snapshot)
  ) {
    return { pages: [await fetchPage(undefined, signal)], reset: true };
  }
  return { pages: reset ? [response] : [...pages, response], reset };
}

export function collectionItems(response: TokenCollection | CandleResponse | undefined) {
  return response?.items ?? [];
}
