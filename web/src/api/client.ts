import type { components, paths } from "./generated";

export type ProtocolDailyResponse =
  paths["/stats/protocol/daily"]["get"]["responses"][200]["content"]["application/json"];
export type ProtocolDailyItem = components["schemas"]["ProtocolDailyDTO"];

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export async function getProtocolDaily(
  baseUrl: string,
  options: { from?: string; to?: string; limit?: number } = {},
): Promise<ProtocolDailyResponse> {
  const url = new URL("/v1/stats/protocol/daily", baseUrl);
  if (options.from) url.searchParams.set("from", options.from);
  if (options.to) url.searchParams.set("to", options.to);
  if (options.limit !== undefined) url.searchParams.set("limit", String(options.limit));
  const response = await fetch(url);
  if (!response.ok) throw new ApiError(response.status, "API request failed");
  return (await response.json()) as ProtocolDailyResponse;
}
