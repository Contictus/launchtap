"use client";
/* Data loading is an external synchronization boundary for this route. */
/* eslint-disable react-hooks/set-state-in-effect */
/* eslint-disable react-hooks/exhaustive-deps */

import { useEffect, useState } from "react";
import { ApiClient, type ProtocolDailyResponse } from "@/api/client";
import { ApiProblem } from "@/api/problems";
import { publicConfiguration } from "@/config/public";
import { formatCanonicalBaseUnits } from "@/amounts";
import { Badge, Button, ErrorState, Skeleton, UnavailableState } from "@/components/primitives";

function eth(value: string) {
  const formatted = formatCanonicalBaseUnits(value, 4);
  return formatted === null ? "Unavailable" : `${formatted} ETH`;
}
function snapshotLabel(snapshot: ProtocolDailyResponse["snapshot"]) {
  return `${snapshot.finality || "unknown"} · block ${snapshot.as_of_block}`;
}

export default function AnalyticsPage() {
  const configuration = publicConfiguration();
  const [summary, setSummary] = useState<Awaited<ReturnType<ApiClient["getProtocol"]>> | null>(
    null,
  );
  const [daily, setDaily] = useState<ProtocolDailyResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const load = async () => {
    if (configuration.status !== "ready" || !configuration.apiBaseUrl) {
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const client = new ApiClient({ baseUrl: configuration.apiBaseUrl });
      const [nextSummary, nextDaily] = await Promise.all([
        client.getProtocol(),
        client.getProtocolDaily({ limit: 366 }),
      ]);
      if (
        nextSummary.snapshot.as_of_block !== nextDaily.snapshot.as_of_block ||
        nextSummary.snapshot.as_of_block_hash !== nextDaily.snapshot.as_of_block_hash
      )
        throw new Error("The API returned mixed canonical snapshots. Refresh to retry.");
      setSummary(nextSummary);
      setDaily(nextDaily);
    } catch (cause) {
      setError(cause instanceof Error ? cause : new Error("Analytics unavailable"));
    } finally {
      setLoading(false);
    }
  };
  useEffect(() => {
    void load();
  }, [configuration.apiBaseUrl, configuration.status]);
  return (
    <div className="page-stack analytics-page">
      <section className="page-hero">
        <div>
          <div className="section-kicker">Analytics</div>
          <h1>Read the launch route.</h1>
          <p className="hero-summary">
            Canonical indexed protocol activity, labelled with the snapshot that produced it.
            ETH-native values are shown without USD enrichment.
          </p>
        </div>
      </section>
      {error ? (
        <ErrorState
          title="Analytics unavailable"
          description={error instanceof ApiProblem ? error.message : error.message}
          action={<Button onClick={() => void load()}>Retry</Button>}
        />
      ) : null}
      {loading ? (
        <div className="analytics-grid">
          {[1, 2, 3, 4].map((item) => (
            <div className="workspace-panel metric-panel" key={item}>
              <Skeleton />
              <Skeleton />
            </div>
          ))}
        </div>
      ) : null}
      {!loading && !error && summary && daily ? (
        <>
          <section className="workspace-panel analytics-snapshot" aria-label="Analytics snapshot">
            <span className="panel-kicker">Protocol snapshot</span>
            <Badge
              tone={
                summary.snapshot.finality === "finalized" || summary.snapshot.finality === "safe"
                  ? "success"
                  : "warning"
              }
            >
              {snapshotLabel(summary.snapshot)}
            </Badge>
            <span className="mono">
              Updated {new Date(summary.updated_at).toLocaleString("en-US")}
            </span>
          </section>
          <section className="analytics-grid" aria-label="Protocol summary">
            <Metric label="24h volume" value={eth(summary.volume_24h_eth)} />
            <Metric label="All-time volume" value={eth(summary.volume_all_time_eth)} />
            <Metric label="24h launches" value={summary.launches_24h.toLocaleString("en-US")} />
            <Metric
              label="All-time launches"
              value={summary.launches_all_time.toLocaleString("en-US")}
            />
            <Metric label="24h trades" value={summary.trades_24h.toLocaleString("en-US")} />
            <Metric
              label="Graduations"
              value={`${summary.graduations_24h.toLocaleString("en-US")} / ${summary.graduations_all_time.toLocaleString("en-US")}`}
            />
          </section>
          <section
            className="workspace-panel analytics-history"
            aria-labelledby="daily-history-title"
          >
            <div className="panel-head">
              <div>
                <p className="panel-kicker">Indexed history</p>
                <h2 id="daily-history-title">Daily activity</h2>
              </div>
              <span className="mono">{daily.items?.length ?? 0} days · ETH only</span>
            </div>
            {daily.items?.length ? (
              <div className="analytics-table" role="table">
                <div className="analytics-row analytics-heading" role="row">
                  <span>Day</span>
                  <span>Volume</span>
                  <span>Launches</span>
                  <span>Trades</span>
                  <span>Graduations</span>
                </div>
                {daily.items.map((item) => (
                  <div className="analytics-row" role="row" key={item.day}>
                    <span className="mono">{item.day}</span>
                    <span className="mono">{eth(item.volume_eth)}</span>
                    <span>{item.launches.toLocaleString("en-US")}</span>
                    <span>{item.trades.toLocaleString("en-US")}</span>
                    <span>{item.graduations.toLocaleString("en-US")}</span>
                  </div>
                ))}
              </div>
            ) : (
              <UnavailableState
                title="No daily history"
                description="The indexer has not published a canonical daily range yet."
              />
            )}
          </section>
          <p className="ui-field-hint">
            Daily values are canonical indexer aggregates. A reorg or stale snapshot can make a
            previous page invalid; refresh returns a single replacement snapshot.
          </p>
        </>
      ) : null}
      {!loading && !error && !summary ? (
        <UnavailableState
          title="Analytics unavailable"
          description="No reviewed API deployment is connected. No sample market values are shown."
        />
      ) : null}
    </div>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <section className="workspace-panel metric-panel">
      <dt>{label}</dt>
      <dd className="mono">{value}</dd>
    </section>
  );
}
