import { describe, expect, it } from "vitest";
import { transformCandles, updateLastCandle } from "./chart-data";

const candle = (overrides: Record<string, string> = {}) => ({
  start: "2026-09-10T12:00:00Z",
  open: "1.1",
  high: "1.4",
  low: "1.0",
  close: "1.3",
  eth_volume: "2.5",
  token_volume: "999999999999999999999",
  trade_count: 2,
  ...overrides,
});

describe("candle chart transformations", () => {
  it("uses candle OHLC and volume only", () => {
    expect(transformCandles([candle()])).toEqual([
      { time: 1789041600, open: 1.1, high: 1.4, low: 1, close: 1.3, volume: 2.5 },
    ]);
  });
  it("drops malformed ranges and updates the last bar incrementally", () => {
    const points = transformCandles([candle({ high: "0.5" })]);
    expect(points).toEqual([]);
    const first = transformCandles([candle()]);
    const next = { ...first[0]!, close: 1.35 };
    expect(updateLastCandle(first, next)).toEqual([next]);
  });
});
