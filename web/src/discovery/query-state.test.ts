import { describe, expect, it } from "vitest";
import {
  decodeTokenListQuery,
  defaultTokenListQuery,
  encodeTokenListQuery,
  commitTokenListFilters,
  normalizeTokenListQuery,
  sameTokenListQuery,
  tokenListFilters,
} from "./query-state";

describe("token discovery URL state", () => {
  it("uses safe defaults and rejects unsupported API values", () => {
    expect(decodeTokenListQuery("?phase=unknown&sort=rank&q=%20%20")).toEqual(
      defaultTokenListQuery(),
    );
    expect(decodeTokenListQuery("", "graduated")).toEqual(defaultTokenListQuery("graduated"));
  });

  it("round trips supported filters and canonicalizes defaults", () => {
    const state = decodeTokenListQuery("?q=red%20%26%20blue&phase=graduated&sort=volume_24h");
    expect(encodeTokenListQuery(state)).toBe("q=red+%26+blue&phase=graduated&sort=volume_24h");
    expect(encodeTokenListQuery(defaultTokenListQuery())).toBe("");
    expect(sameTokenListQuery(state, decodeTokenListQuery(encodeTokenListQuery(state)))).toBe(true);
  });

  it("forces the graduated route to remain graduated and removes a conflicting URL phase", () => {
    const conflicting = decodeTokenListQuery("?phase=curve&sort=market_cap", "graduated");
    expect(conflicting.phase).toBe("curve");
    const normalized = normalizeTokenListQuery(conflicting, "graduated");
    expect(normalized.phase).toBe("graduated");
    expect(encodeTokenListQuery(normalized, "graduated")).toBe("sort=market_cap");
  });

  it("maps exactly to the generated GET /v1/tokens query", () => {
    expect(tokenListFilters({ q: "  coin ", phase: "curve", sort: "market_cap" })).toEqual({
      q: "  coin ",
      phase: "curve",
      sort: "market_cap",
      limit: 20,
    });
  });

  it("commits a pending search draft when another filter changes", () => {
    expect(
      commitTokenListFilters({ q: "old", phase: "curve", sort: "newest" }, "fresh search", {
        sort: "volume_24h",
      }),
    ).toEqual({ q: "fresh search", phase: "curve", sort: "volume_24h" });
  });
});
