import { describe, expect, it } from "vitest";
import { transformCandles, updateLastCandle } from "./chart-data";

const candle = (overrides: Record<string, string> = {}) => ({
  start: "2026-09-10T12:00:00Z",
  open: "1100000000000000000",
  high: "1400000000000000000",
  low: "1000000000000000000",
  close: "1300000000000000000",
  eth_volume: "2500000000000000000",
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
    const points = transformCandles([candle({ high: "500000000000000000" })]);
    expect(points).toEqual([]);
    const first = transformCandles([candle()]);
    const next = { ...first[0]!, close: 1.35 };
    expect(updateLastCandle(first, next)).toEqual([next]);
  });
  it("fails closed for malformed, signed, hexadecimal, and unbounded WAD values", () => {
    for (const value of ["", " ", "+1", "-1", "0x1", "1.0", "1e18"])
      expect(transformCandles([candle({ open: value })])).toEqual([]);
    expect(
      transformCandles([
        candle({
          open: "1000000000000000000000000000000000000000000000",
        }),
      ]),
    ).toEqual([]);
  });
});
