import { describe, expect, it } from "vitest";
import { ApiProblem } from "@/api/problems";
import type { TokenListResponse } from "@/api/client";
import { loadTokenDiscoveryPage } from "./controller";

const snapshot = (block: number) => ({
  chain_id: 46630,
  as_of_block: block,
  as_of_block_hash: `0x${block}`,
  finality: "safe",
});

const page = (block: number, name: string, next_cursor?: string): TokenListResponse => ({
  items: [
    {
      address: "0x0000000000000000000000000000000000000001",
      holder_count: 1,
      launch_block: block,
      launch_time: "2026-09-10T00:00:00.000000Z",
      market_cap_eth: "0",
      name,
      phase: "curve",
      symbol: "TST",
      total_supply: "1000000000000000000",
      volume_24h_eth: "0",
    },
  ],
  next_cursor,
  snapshot: snapshot(block),
});

const state = { q: "", phase: "curve" as const, sort: "newest" as const };

describe("token discovery append recovery", () => {
  it("discards the cursor chain after cursor invalidation and refetches page one once", async () => {
    const requests: Array<string | undefined> = [];
    const responses = [page(10, "fresh", "cursor-2")];
    const result = await loadTokenDiscoveryPage({
      state,
      cursor: "cursor-1",
      existingPages: [page(10, "stale", "cursor-1")],
      fetchPage: async (query) => {
        requests.push(query.cursor);
        if (requests.length === 1) throw new ApiProblem(409, "cursor_invalidated");
        return responses[0]!;
      },
    });
    expect(requests).toEqual(["cursor-1", undefined]);
    expect(result.reset).toBe(true);
    expect(result.pages).toHaveLength(1);
    expect(result.pages[0]?.items?.[0]?.name).toBe("fresh");
  });

  it("treats invalid_cursor as a one-shot page-one recovery", async () => {
    const requests: Array<string | undefined> = [];
    const result = await loadTokenDiscoveryPage({
      state,
      cursor: "cursor-1",
      existingPages: [page(10, "stale", "cursor-1"), page(10, "older")],
      fetchPage: async (query) => {
        requests.push(query.cursor);
        if (requests.length === 1) throw new ApiProblem(400, "invalid_cursor");
        return page(12, "recovered", "cursor-2");
      },
    });
    expect(requests).toEqual(["cursor-1", undefined]);
    expect(result.reset).toBe(true);
    expect(result.pages).toHaveLength(1);
    expect(result.pages[0]?.items?.[0]?.name).toBe("recovered");
  });

  it("discards accumulated pages when the cursor response changes snapshot", async () => {
    const requests: Array<string | undefined> = [];
    const result = await loadTokenDiscoveryPage({
      state,
      cursor: "cursor-1",
      existingPages: [page(10, "stale", "cursor-1")],
      fetchPage: async (query) => {
        requests.push(query.cursor);
        return query.cursor ? page(11, "mismatched") : page(12, "recovered", "cursor-2");
      },
    });
    expect(requests).toEqual(["cursor-1", undefined]);
    expect(result.reset).toBe(true);
    expect(result.pages).toHaveLength(1);
    expect(result.pages[0]?.items?.[0]?.name).toBe("recovered");
  });

  it("appends a matching cursor page without discarding the existing chain", async () => {
    const result = await loadTokenDiscoveryPage({
      state,
      cursor: "cursor-1",
      existingPages: [page(10, "first", "cursor-1")],
      fetchPage: async () => page(10, "second"),
    });
    expect(result.reset).toBe(false);
    expect(result.pages.map((entry) => entry.items?.[0]?.name)).toEqual(["first", "second"]);
  });
});
