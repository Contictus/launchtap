export const TOKEN_LIST_LIMIT = 20;
export const TOKEN_PHASES = ["curve", "graduated"] as const;
export type TokenPhase = (typeof TOKEN_PHASES)[number];
export const TOKEN_SORTS = ["newest", "oldest", "market_cap", "volume_24h"] as const;
export type TokenSort = (typeof TOKEN_SORTS)[number];

export type TokenListQueryState = {
  q: string;
  phase: TokenPhase;
  sort: TokenSort;
};

export const SORT_LABELS: Record<TokenSort, string> = {
  newest: "Newest launches",
  oldest: "Oldest launches",
  market_cap: "Market cap",
  volume_24h: "24h volume",
};

export const PHASE_LABELS: Record<TokenPhase, string> = {
  curve: "Curve",
  graduated: "Graduated",
};

export function defaultTokenListQuery(defaultPhase: TokenPhase = "curve"): TokenListQueryState {
  return { q: "", phase: defaultPhase, sort: "newest" };
}

function isPhase(value: string | null): value is TokenPhase {
  return value !== null && (TOKEN_PHASES as readonly string[]).includes(value);
}

function isSort(value: string | null): value is TokenSort {
  return value !== null && (TOKEN_SORTS as readonly string[]).includes(value);
}

/** Parse only the filters supported by GET /v1/tokens; malformed values fall back safely. */
export function decodeTokenListQuery(
  input: string | URLSearchParams,
  defaultPhase: TokenPhase = "curve",
): TokenListQueryState {
  const params = typeof input === "string" ? new URLSearchParams(input) : input;
  const rawQ = params.get("q") ?? "";
  const rawPhase = params.get("phase");
  const rawSort = params.get("sort");
  return {
    q: rawQ.trim(),
    phase: isPhase(rawPhase) ? rawPhase : defaultPhase,
    sort: isSort(rawSort) ? rawSort : "newest",
  };
}

/** Canonical, shareable URL state. Defaults are omitted to keep links stable and readable. */
export function encodeTokenListQuery(
  state: TokenListQueryState,
  defaultPhase: TokenPhase = "curve",
) {
  const params = new URLSearchParams();
  if (state.q.trim()) params.set("q", state.q.trim());
  if (state.phase !== defaultPhase) params.set("phase", state.phase);
  if (state.sort !== "newest") params.set("sort", state.sort);
  return params.toString();
}

export function tokenListFilters(state: TokenListQueryState) {
  return { phase: state.phase, q: state.q, sort: state.sort, limit: TOKEN_LIST_LIMIT };
}

export function sameTokenListQuery(a: TokenListQueryState, b: TokenListQueryState) {
  return a.q === b.q && a.phase === b.phase && a.sort === b.sort;
}

export function normalizeTokenListQuery(
  state: TokenListQueryState,
  defaultPhase: TokenPhase = "curve",
): TokenListQueryState {
  return defaultPhase === "graduated" ? { ...state, phase: "graduated" } : state;
}

export function commitTokenListFilters(
  state: TokenListQueryState,
  currentSearchDraft: string,
  changes: Partial<Pick<TokenListQueryState, "phase" | "sort">>,
): TokenListQueryState {
  return { ...state, ...changes, q: currentSearchDraft.trim() };
}
