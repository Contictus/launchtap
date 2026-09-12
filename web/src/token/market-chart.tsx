"use client";

import { useEffect, useRef } from "react";
import {
  AreaSeries,
  CandlestickSeries,
  ColorType,
  HistogramSeries,
  createChart,
  type IChartApi,
} from "lightweight-charts";
import { setChartSnapshot, type CandleChartPoint, type ChartSnapshotSeries } from "./chart-data";

export function MarketChart({
  points,
  mode,
}: {
  points: CandleChartPoint[];
  mode: "area" | "candles";
}) {
  const hostRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<IChartApi | null>(null);
  const seriesRef = useRef<{
    setData: (data: unknown[]) => void;
  } | null>(null);
  const volumeRef = useRef<{ setData: (data: unknown[]) => void } | null>(null);

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;
    const chart = createChart(host, {
      autoSize: false,
      width: host.clientWidth,
      height: 300,
      layout: { background: { type: ColorType.Solid, color: "#0E1B2A" }, textColor: "#AAB7C5" },
      grid: { vertLines: { color: "#1b3044" }, horzLines: { color: "#1b3044" } },
      rightPriceScale: { borderColor: "#263B50" },
      timeScale: { borderColor: "#263B50", timeVisible: true },
    });
    chartRef.current = chart;
    const priceSeries =
      mode === "candles"
        ? chart.addSeries(CandlestickSeries, {
            upColor: "#82D9A2",
            downColor: "#E45756",
            borderVisible: false,
            wickUpColor: "#82D9A2",
            wickDownColor: "#E45756",
          })
        : chart.addSeries(AreaSeries, {
            lineColor: "#E45756",
            topColor: "rgba(228,87,86,0.2)",
            bottomColor: "rgba(228,87,86,0)",
          });
    const volumeSeries = chart.addSeries(HistogramSeries, {
      priceFormat: { type: "volume" },
      priceScaleId: "volume",
      color: "#38516B",
    });
    chart.priceScale("volume").applyOptions({ scaleMargins: { top: 0.78, bottom: 0 } });
    setChartSnapshot(
      priceSeries as unknown as ChartSnapshotSeries,
      volumeSeries as unknown as ChartSnapshotSeries,
      points,
      mode,
    );
    seriesRef.current = priceSeries as unknown as {
      setData: (data: unknown[]) => void;
    };
    volumeRef.current = volumeSeries as unknown as { setData: (data: unknown[]) => void };
    chart.timeScale().fitContent();
    const observer = new ResizeObserver(() => {
      if (host.clientWidth > 0) chart.applyOptions({ width: host.clientWidth });
    });
    observer.observe(host);
    return () => {
      observer.disconnect();
      seriesRef.current = null;
      volumeRef.current = null;
      chartRef.current = null;
      chart.remove();
    };
    // Recreate only when the mode or point count changes; snapshots replace series data below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode, points.length]);

  useEffect(() => {
    const series = seriesRef.current;
    const volume = volumeRef.current;
    if (!series || !volume) return;
    setChartSnapshot(series, volume, points, mode);
  }, [mode, points]);

  return (
    <div className="market-chart-wrap">
      {points.length ? (
        <div ref={hostRef} className="market-chart" aria-label={`${mode} market chart`} />
      ) : (
        <p className="chart-empty">No candles in this range.</p>
      )}
      <p className="chart-attribution">
        Market data from indexed candle snapshots ·{" "}
        <a href="https://www.tradingview.com" target="_blank" rel="noopener noreferrer">
          TradingView Lightweight Charts
        </a>
      </p>
    </div>
  );
}
