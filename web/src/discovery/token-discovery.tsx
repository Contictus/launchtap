"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ApiClient, type TokenListQuery, type TokenListResponse } from "@/api/client";
import type { components } from "@/api/generated";
import { ApiProblem } from "@/api/problems";
import { queryKeys, snapshotIdentity, type Snapshot } from "@/api/types";
import { SseInvalidationStream } from "@/api/sse";
import { formatDisplayAmount } from "@/amounts";
import { publicConfiguration } from "@/config/public";
import {
  decodeTokenListQuery,
  commitTokenListFilters,
  defaultTokenListQuery,
  encodeTokenListQuery,
  normalizeTokenListQuery,
  PHASE_LABELS,
  SORT_LABELS,
  sameTokenListQuery,
  TOKEN_PHASES,
  TOKEN_SORTS,
  tokenListFilters,
  type TokenListQueryState,
  type TokenPhase,
} from "./query-state";
import { loadTokenDiscoveryPage } from "./controller";
import {
  Badge,
  Button,
  EmptyState,
  ErrorState,
  Input,
  SafeImage,
  Skeleton,
} from "@/components/primitives";

export type TokenListFetcher = (
  query: TokenListQuery,
  signal?: AbortSignal,
) => Promise<TokenListResponse>;

type TokenDiscoveryProps = {
  defaultPhase?: TokenPhase;
  title: string;
  summary: string;
  fetchPage?: TokenListFetcher;
};
type TokenCardData = components["schemas"]["TokenDTO"];

function displayAmount(raw: string, decimals = 18) {
  try {
    return formatDisplayAmount(BigInt(raw), decimals, 4);
  } catch {
    return "Unavailable";
  }
}

function finalityTone(finality: string): "success" | "warning" | "neutral" {
  return finality === "safe" || finality === "finalized"
    ? "success"
    : finality === "provisional" || finality === "stale"
      ? "warning"
      : "neutral";
}

function finalityLabel(finality: string) {
  if (finality === "safe") return "Safe snapshot";
  if (finality === "finalized") return "Finalized snapshot";
  if (finality === "provisional") return "Provisional snapshot";
  if (finality === "stale") return "Stale snapshot";
  return finality ? `${finality} snapshot` : "Snapshot status unavailable";
}

function tokenLabel(token: TokenCardData) {
  return token.name.trim() || token.symbol.trim() || "Unnamed token";
}

export function TokenDiscovery({
  defaultPhase = "curve",
  title,
  summary,
  fetchPage: injectedFetcher,
}: TokenDiscoveryProps) {
  const configuration = publicConfiguration();
  const pathname = usePathname();
  const router = useRouter();
  const searchParams = useSearchParams();
  const urlState = useMemo(
    () =>
      normalizeTokenListQuery(
        decodeTokenListQuery(searchParams.toString(), defaultPhase),
        defaultPhase,
      ),
    [defaultPhase, searchParams],
  );
  const [searchDraft, setSearchDraft] = useState(urlState.q);
  const [pages, setPages] = useState<TokenListResponse[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<ApiProblem | Error | null>(null);
  const [resetNotice, setResetNotice] = useState(false);
  const pagesRef = useRef<TokenListResponse[]>([]);
  const requestId = useRef(0);
  const abortRef = useRef<AbortController | null>(null);
  const latestState = useRef(urlState);
  const searchEditedRef = useRef(false);
  const chainSnapshotRef = useRef<Snapshot | undefined>(undefined);
  const refreshTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    latestState.current = urlState;
    searchEditedRef.current = false;
    // URL navigation is an external synchronization point, including browser back/forward.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setSearchDraft(urlState.q);
  }, [urlState]);

  const writeUrlState = useCallback(
    (next: TokenListQueryState, replace = false) => {
      const query = encodeTokenListQuery(normalizeTokenListQuery(next, defaultPhase), defaultPhase);
      const target = query ? `${pathname}?${query}` : pathname;
      if (replace) router.replace(target as never, { scroll: false });
      else router.push(target as never, { scroll: false });
    },
    [defaultPhase, pathname, router],
  );

  useEffect(() => {
    if (defaultPhase !== "graduated" || searchParams.get("phase") === null) return;
    const query = encodeTokenListQuery(urlState, defaultPhase);
    router.replace((query ? `${pathname}?${query}` : pathname) as never, { scroll: false });
  }, [defaultPhase, pathname, router, searchParams, urlState]);

  useEffect(() => {
    const timer = setTimeout(() => {
      if (!searchEditedRef.current || searchDraft.trim() === urlState.q) return;
      writeUrlState({ ...urlState, q: searchDraft.trim() });
    }, 300);
    return () => clearTimeout(timer);
  }, [searchDraft, urlState, writeUrlState]);

  const loadPage = useCallback(
    async (
      state: TokenListQueryState,
      cursor?: string,
      append = false,
      externalSignal?: AbortSignal,
    ) => {
      if (configuration.status !== "ready" || !configuration.apiBaseUrl) {
        setLoading(false);
        setLoadingMore(false);
        return;
      }
      abortRef.current?.abort();
      const controller = new AbortController();
      abortRef.current = controller;
      const abortFromOutside = () => controller.abort();
      externalSignal?.addEventListener("abort", abortFromOutside, { once: true });
      const currentRequest = ++requestId.current;
      setError(null);
      if (append) setLoadingMore(true);
      else {
        setLoading(true);
        setPages([]);
        pagesRef.current = [];
        chainSnapshotRef.current = undefined;
      }
      const fetchPage = injectedFetcher
        ? injectedFetcher
        : (query: TokenListQuery, signal?: AbortSignal) =>
            new ApiClient({ baseUrl: configuration.apiBaseUrl! }).getTokens(query, signal);
      try {
        const result = await loadTokenDiscoveryPage({
          fetchPage,
          state,
          cursor: append ? cursor : undefined,
          existingPages: pagesRef.current,
          signal: controller.signal,
        });
        if (controller.signal.aborted || currentRequest !== requestId.current) return;
        pagesRef.current = result.pages;
        chainSnapshotRef.current = result.pages[0]?.snapshot;
        setPages(result.pages);
        setResetNotice(result.reset);
      } catch (cause) {
        if (controller.signal.aborted || currentRequest !== requestId.current) return;
        setError(cause instanceof Error ? cause : new Error("The token list could not be loaded."));
        if (!append) {
          pagesRef.current = [];
          setPages([]);
        }
      } finally {
        externalSignal?.removeEventListener("abort", abortFromOutside);
        if (currentRequest === requestId.current) {
          setLoading(false);
          setLoadingMore(false);
        }
      }
    },
    [configuration.apiBaseUrl, configuration.status, injectedFetcher],
  );
  useEffect(() => {
    // Fetching is the intended synchronization with the external API when URL state changes.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void loadPage(urlState);
    return () => abortRef.current?.abort();
  }, [loadPage, urlState]);

  useEffect(() => {
    if (configuration.status !== "ready" || !configuration.apiBaseUrl || injectedFetcher) return;
    const stream = new SseInvalidationStream({
      url: `${configuration.apiBaseUrl}/v1/events`,
      queryClient: {
        invalidateQueries: async () => {
          if (refreshTimerRef.current) return;
          refreshTimerRef.current = setTimeout(() => {
            refreshTimerRef.current = null;
            void loadPage(latestState.current, undefined, false);
          }, 80);
        },
      },
      queryKeyForEvent: (event) => {
        if (
          event.data.chain_id !== configuration.chainId ||
          event.data.deployment_id !== configuration.deploymentId
        )
          return undefined;
        return queryKeys.tokens(
          configuration.chainId,
          configuration.deploymentId,
          tokenListFilters(latestState.current),
          chainSnapshotRef.current,
        );
      },
      refetchSnapshot: async (signal) => {
        void signal;
        await loadPage(latestState.current, undefined, false, signal);
      },
    });
    const stop = stream.start();
    return () => {
      stop();
      if (refreshTimerRef.current) clearTimeout(refreshTimerRef.current);
      refreshTimerRef.current = null;
    };
  }, [
    configuration.apiBaseUrl,
    configuration.chainId,
    configuration.deploymentId,
    configuration.status,
    injectedFetcher,
    loadPage,
  ]);

  const firstPage = pages[0];
  const snapshot: Snapshot | undefined = firstPage?.snapshot;
  const items = pages.flatMap((page) => page.items ?? []);
  const nextCursor = pages.at(-1)?.next_cursor;
  const queryKey = queryKeys.tokens(
    configuration.chainId,
    configuration.deploymentId,
    tokenListFilters(urlState),
    snapshot,
  );

  const commitFilters = (changes: Partial<Pick<TokenListQueryState, "phase" | "sort">>) => {
    searchEditedRef.current = false;
    writeUrlState(commitTokenListFilters(urlState, searchDraft, changes));
  };
  const choosePhase = (phase: TokenPhase) => commitFilters({ phase });
  const chooseSort = (sort: TokenListQueryState["sort"]) => commitFilters({ sort });
  const retry = () => void loadPage(urlState);

  return (
    <div className="page-stack discovery-page" data-query-key={JSON.stringify(queryKey)}>
      <section className="page-hero" aria-labelledby="discovery-title">
        <div>
          <div className="section-kicker">Token ledger</div>
          <h1 id="discovery-title">{title}</h1>
          <p className="hero-summary">{summary}</p>
        </div>
        <div className="hero-aside">
          <span className="hero-rule" />
          <p>
            Indexed reads stay separate from wallet signing. Every row carries its snapshot state.
          </p>
          <Badge tone={configuration.status === "ready" ? "success" : "warning"}>
            {configuration.status === "ready" ? "API connected" : "API unavailable · fail-closed"}
          </Badge>
          {configuration.status !== "ready" ? (
            <span className="mono discovery-config-note">Not configured</span>
          ) : null}
        </div>
      </section>

      <section className="workspace-panel discovery-panel" aria-labelledby="list-title">
        <div className="panel-head discovery-controls-head">
          <div>
            <p className="panel-kicker">GET /v1/tokens</p>
            <h2 id="list-title">
              {urlState.phase === "graduated" ? "Graduated routes" : "Curve routes"}
            </h2>
          </div>
          {snapshot ? <SnapshotBadge snapshot={snapshot} /> : null}
        </div>
        <div className="discovery-controls" role="search">
          <Input
            label="Search tokens"
            placeholder="Name or symbol"
            value={searchDraft}
            onChange={(event) => {
              searchEditedRef.current = true;
              setSearchDraft(event.target.value);
            }}
            maxLength={120}
            autoComplete="off"
          />
          {defaultPhase !== "graduated" ? (
            <label className="ui-field">
              <span>Phase</span>
              <select
                className="ui-input"
                value={urlState.phase}
                onChange={(event) => choosePhase(event.target.value as TokenPhase)}
              >
                {TOKEN_PHASES.map((phase) => (
                  <option key={phase} value={phase}>
                    {PHASE_LABELS[phase]}
                  </option>
                ))}
              </select>
            </label>
          ) : null}
          <label className="ui-field">
            <span>Sort</span>
            <select
              className="ui-input"
              value={urlState.sort}
              onChange={(event) => chooseSort(event.target.value as TokenListQueryState["sort"])}
            >
              {TOKEN_SORTS.map((sort) => (
                <option key={sort} value={sort}>
                  {SORT_LABELS[sort]}
                </option>
              ))}
            </select>
          </label>
        </div>
        {resetNotice ? (
          <p className="discovery-notice" role="status">
            This page marker expired. Showing page one from a fresh snapshot.
          </p>
        ) : null}
        {configuration.status !== "ready" ? (
          <div className="discovery-state">
            <UnavailableDiscovery />
          </div>
        ) : error ? (
          <div className="discovery-state">
            <ErrorState
              title="Token list unavailable"
              description={
                error instanceof ApiProblem
                  ? error.message
                  : "The API could not be reached. Try again."
              }
              action={<Button onClick={retry}>Retry</Button>}
            />
          </div>
        ) : loading ? (
          <TokenListSkeleton />
        ) : items.length === 0 ? (
          <div className="discovery-state">
            <EmptyState
              title={urlState.q ? "No matching tokens" : "No indexed tokens yet"}
              description={
                urlState.q
                  ? "Try a different name or symbol."
                  : "The connected API has no tokens for this route yet."
              }
              action={
                urlState.q ? (
                  <Button
                    variant="quiet"
                    onClick={() => {
                      setSearchDraft("");
                      writeUrlState({ ...urlState, q: "" });
                    }}
                  >
                    Clear search
                  </Button>
                ) : null
              }
            />
          </div>
        ) : (
          <>
            <div className="token-list" aria-live="polite" aria-busy={loadingMore}>
              {items.map((token) => (
                <TokenCard key={token.address} token={token} />
              ))}
            </div>
            <div className="discovery-pagination">
              <span className="discovery-count">
                Showing {items.length} indexed {items.length === 1 ? "route" : "routes"}; total
                count unavailable.
              </span>
              {nextCursor ? (
                <Button
                  loading={loadingMore}
                  onClick={() => void loadPage(urlState, nextCursor, true)}
                >
                  Load more
                </Button>
              ) : (
                <span className="discovery-end">End of snapshot</span>
              )}
            </div>
          </>
        )}
      </section>
    </div>
  );
}

function SnapshotBadge({ snapshot }: { snapshot: Snapshot }) {
  return (
    <div className="snapshot-badge">
      <Badge tone={finalityTone(snapshot.finality)}>{finalityLabel(snapshot.finality)}</Badge>
      <span className="mono">Block {snapshot.as_of_block}</span>
    </div>
  );
}

function TokenCard({ token }: { token: TokenCardData }) {
  const label = tokenLabel(token);
  return (
    <article className="token-card">
      <div className="token-card-main">
        <SafeImage
          src={undefined}
          alt={`${label} token`}
          fallbackLabel="No token image"
          className="token-image"
        />
        <div className="token-identity">
          <h3>{label}</h3>
          <p className="mono token-symbol">{token.symbol || "—"}</p>
          <p className="mono token-address">{token.address}</p>
        </div>
        <Badge tone={token.phase === "graduated" ? "success" : "accent"}>{token.phase}</Badge>
      </div>
      <dl className="token-metrics">
        <div>
          <dt>Market cap</dt>
          <dd>{displayAmount(token.market_cap_eth)} ETH</dd>
        </div>
        <div>
          <dt>24h volume</dt>
          <dd>{displayAmount(token.volume_24h_eth)} ETH</dd>
        </div>
        <div>
          <dt>Holders</dt>
          <dd>{token.holder_count.toLocaleString("en-US")}</dd>
        </div>
        <div>
          <dt>Launch block</dt>
          <dd>{token.launch_block.toLocaleString("en-US")}</dd>
        </div>
      </dl>
    </article>
  );
}

function TokenListSkeleton() {
  return (
    <div className="token-list" aria-label="Loading token routes" aria-busy="true">
      {Array.from({ length: 4 }, (_, index) => (
        <div className="token-card token-card-skeleton" key={index}>
          <Skeleton className="token-image" />
          <div className="token-skeleton-copy">
            <Skeleton />
            <Skeleton />
            <Skeleton />
          </div>
        </div>
      ))}
    </div>
  );
}

function UnavailableDiscovery() {
  return (
    <section className="ui-state ui-unavailable" aria-live="polite">
      <span className="ui-state-mark" aria-hidden="true">
        /
      </span>
      <div>
        <h2>Indexed discovery unavailable</h2>
        <p>
          Connect a reviewed API and deployment to load current tokens. Cached values are not
          presented as current.
        </p>
      </div>
    </section>
  );
}

export function canonicalDiscoveryQuery(search: string, defaultPhase: TokenPhase = "curve") {
  return encodeTokenListQuery(
    normalizeTokenListQuery(decodeTokenListQuery(search, defaultPhase), defaultPhase),
    defaultPhase,
  );
}

export {
  defaultTokenListQuery,
  decodeTokenListQuery,
  encodeTokenListQuery,
  sameTokenListQuery,
  snapshotIdentity,
};
