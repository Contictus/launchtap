import type { components, paths } from "./generated";
import { mapProblem } from "./problems";

export type ProtocolDailyResponse =
  paths["/stats/protocol/daily"]["get"]["responses"][200]["content"]["application/json"];
export type ProtocolDailyItem = components["schemas"]["ProtocolDailyDTO"];
export type AuthHeaders = { accessToken?: string; identityToken?: string };

export class ApiClient {
  private readonly fetchImpl: typeof globalThis.fetch;
  constructor(private readonly options: { baseUrl: string; fetch?: typeof globalThis.fetch }) {
    this.fetchImpl = options.fetch ?? globalThis.fetch;
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

  getToken(address: string) {
    return this.request<components["schemas"]["TokenDetailDTO"]>(
      `/v1/tokens/${encodeURIComponent(address)}`,
    );
  }
}

export function getProtocolDaily(
  baseUrl: string,
  options: { from?: string; to?: string; limit?: number } = {},
) {
  return new ApiClient({ baseUrl }).getProtocolDaily(options);
}
