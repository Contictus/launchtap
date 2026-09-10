import { describe, expect, it, vi } from "vitest";
import { ApiProblem } from "@/api/problems";
import { appendTokenCollectionPage } from "./pagination";

const snapshot = { chain_id: 1, as_of_block: 10, as_of_block_hash: "0x1", finality: "safe" };
const page = (cursor?: string, snap = snapshot) => ({
  items: [],
  next_cursor: cursor,
  snapshot: snap,
});

describe("token collection pagination", () => {
  it("recovers invalid cursors from page one", async () => {
    const fetch = vi
      .fn()
      .mockRejectedValueOnce(new ApiProblem(409, "cursor_invalidated"))
      .mockResolvedValueOnce(page("next"));
    const result = await appendTokenCollectionPage(fetch, [page("cursor")], "cursor");
    expect(result.reset).toBe(true);
    expect(fetch).toHaveBeenLastCalledWith(undefined, undefined);
  });
  it("resets when a response changes snapshots", async () => {
    const fetch = vi
      .fn()
      .mockResolvedValueOnce(page("other", { ...snapshot, as_of_block: 11 }))
      .mockResolvedValueOnce(page());
    const result = await appendTokenCollectionPage(fetch, [page("cursor")], "cursor");
    expect(result.reset).toBe(true);
    expect(result.pages).toHaveLength(1);
  });
});
