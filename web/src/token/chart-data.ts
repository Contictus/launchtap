import type { components } from "@/api/generated";
import { wadToBoundedNumber } from "@/amounts";

export type CandleChartPoint = {
  time: number;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
};

/** Chart values are decimal spot/volume strings from CandleDTO only, never trade execution data. */
export function transformCandles(candles: readonly components["schemas"]["CandleDTO"][] | null) {
  if (!candles) return [];
  const points: CandleChartPoint[] = [];
  for (const candle of candles) {
    const time = Date.parse(candle.start) / 1000;
    const values = [candle.open, candle.high, candle.low, candle.close, candle.eth_volume].map(
      (value) => wadToBoundedNumber(value),
    );
    if (
      !Number.isFinite(time) ||
      !Number.isInteger(time) ||
      values.some((value) => value === null || !Number.isFinite(value) || value < 0)
    )
      continue;
    const [open, high, low, close, volume] = values as [number, number, number, number, number];
    if (high < low || open < low || open > high || close < low || close > high) continue;
    points.push({ time, open, high, low, close, volume });
  }
  return points.sort((a, b) => a.time - b.time);
}

export function updateLastCandle(
  existing: readonly CandleChartPoint[],
  next: CandleChartPoint,
): CandleChartPoint[] {
  const result = [...existing];
  const last = result.at(-1);
  if (last?.time === next.time) result[result.length - 1] = next;
  else if (!last || next.time > last.time) result.push(next);
  return result;
}
