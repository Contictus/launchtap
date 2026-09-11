import { describe, expect, it } from "vitest";
import { queryKeys, stableSerialize } from "./types";

const snapshot = { chain_id: 46630, as_of_block: 12, as_of_block_hash: "0xabc", finality: "safe" };

describe("snapshot-bound query keys", () => {
  it("serializes object keys deterministically", () => {
    expect(stableSerialize({ b: 2, a: 1 })).toBe(stableSerialize({ a: 1, b: 2 }));
  });

  it("keeps token detail and protocol daily snapshots distinct", () => {
    const next = { ...snapshot, as_of_block: 13 };
    expect(queryKeys.token(46630, "deployment", "0xAbC", snapshot)).not.toEqual(
      queryKeys.token(46630, "deployment", "0xAbC", next),
    );
    expect(queryKeys.protocolDaily(46630, "deployment", {}, snapshot)).not.toEqual(
      queryKeys.protocolDaily(46630, "deployment", {}, next),
    );
  });
});
