import type { components, paths } from "./generated";
import { mapProblem } from "./problems";

export type ProtocolDailyResponse =
  paths["/stats/protocol/daily"]["get"]["responses"][200]["content"]["application/json"];
export type ProtocolDailyItem = components["schemas"]["ProtocolDailyDTO"];
export type TokenListResponse = components["schemas"]["TokenListBody"];
export type TokenDetailResponse = components["schemas"]["TokenDetailDTO"];
export type CandleResponse = components["schemas"]["CandleBody"];
export type TradesResponse = components["schemas"]["TradesBody"];
export type HoldersResponse = components["schemas"]["HoldersBody"];
export type QuoteResponse = components["schemas"]["QuoteBody"];
export type TokenListQuery = {
  phase?: string;
  q?: string;
  sort?: string;
  cursor?: string;
  limit?: number;
};
export type AuthHeaders = { accessToken?: string; identityToken?: string };

export class ApiClient {
  private readonly fetchImpl: typeof globalThis.fetch;
  constructor(private readonly options: { baseUrl: string; fetch?: typeof globalThis.fetch }) {
    this.fetchImpl = options.fetch ?? ((input, init) => globalThis.fetch(input, init));
  }

  async request<T>(path: string, init: RequestInit = {}, auth?: AuthHeaders): Promise<T> {
    const url = new URL(path, this.options.baseUrl);
    for (const key of url.searchParams.keys()) {
      if (/authorization|token|signature|secret|private|password/i.test(key))
        throw new Error("Sensitive values are not permitted in request URLs");
    }
    const headers = new Headers(init.headers);
    headers.set("Accept", "application/json");
    if (auth?.accessToken) headers.set("Authorization", `Bearer ${auth.accessToken}`);
    if (auth?.identityToken) headers.set("privy-id-token", auth.identityToken);
    const response = await this.fetchImpl(url, { ...init, headers });
    if (!response.ok) {
      let body: unknown;
      try {
        body = await response.json();
      } catch {
        body = undefined;
      }
      throw mapProblem(response.status, body);
    }
    return (await response.json()) as T;
  }

  getProtocolDaily(options: { from?: string; to?: string; limit?: number } = {}) {
    const query = new URLSearchParams();
    for (const [key, value] of Object.entries(options))
      if (value !== undefined) query.set(key, String(value));
    return this.request<ProtocolDailyResponse>(
      `/v1/stats/protocol/daily${query.size ? `?${query}` : ""}`,
    );
  }

  getToken(address: string, signal?: AbortSignal) {
    return this.request<TokenDetailResponse>(`/v1/tokens/${encodeURIComponent(address)}`, {
      signal,
    });
  }

  getCandles(
    address: string,
    options: {
      interval?: string;
      from?: string;
      to?: string;
      limit?: number;
      cursor?: string;
    } = {},
    signal?: AbortSignal,
  ) {
    const query = new URLSearchParams();
    for (const [key, value] of Object.entries(options)) {
      if (value !== undefined && value !== "") query.set(key, String(value));
    }
    return this.request<CandleResponse>(
      `/v1/tokens/${encodeURIComponent(address)}/candles${query.size ? `?${query}` : ""}`,
      { signal },
    );
  }

  getTrades(
    address: string,
    options: { cursor?: string; limit?: number } = {},
    signal?: AbortSignal,
  ) {
    return this.getCursorCollection<TradesResponse>(address, "trades", options, signal);
  }

  getHolders(
    address: string,
    options: { cursor?: string; limit?: number } = {},
    signal?: AbortSignal,
  ) {
    return this.getCursorCollection<HoldersResponse>(address, "holders", options, signal);
  }

  private getCursorCollection<T>(
    address: string,
    resource: "trades" | "holders",
    options: { cursor?: string; limit?: number },
    signal?: AbortSignal,
  ) {
    const query = new URLSearchParams();
    for (const [key, value] of Object.entries(options)) {
      if (value !== undefined && value !== "") query.set(key, String(value));
    }
    return this.request<T>(
      `/v1/tokens/${encodeURIComponent(address)}/${resource}${query.size ? `?${query}` : ""}`,
      { signal },
    );
  }

  getTokens(options: TokenListQuery = {}, signal?: AbortSignal) {
    const query = new URLSearchParams();
    for (const [key, value] of Object.entries(options)) {
      if (value !== undefined && value !== "") query.set(key, String(value));
    }
    return this.request<TokenListResponse>(
      `/v1/tokens${query.size ? `?${query.toString()}` : ""}`,
      { signal },
    );
  }

  getQuote(address: string, input: components["schemas"]["QuoteInputBody"], signal?: AbortSignal) {
    return this.request<QuoteResponse>(`/v1/tokens/${encodeURIComponent(address)}/quote`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(input),
      signal,
    });
  }
}

export function getProtocolDaily(
  baseUrl: string,
  options: { from?: string; to?: string; limit?: number } = {},
) {
  return new ApiClient({ baseUrl }).getProtocolDaily(options);
}

export function getTokens(baseUrl: string, options: TokenListQuery = {}, signal?: AbortSignal) {
  return new ApiClient({ baseUrl }).getTokens(options, signal);
}
