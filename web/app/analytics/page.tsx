"use client";

import { useState } from "react";
import { RoutePlaceholder } from "@/components/route-placeholder";
import { Tabs } from "@/components/primitives";

export default function AnalyticsPage() {
  const [view, setView] = useState("overview");
  return (
    <>
      <RoutePlaceholder
        eyebrow="Analytics"
        title="Read the launch route."
        summary="Protocol analytics will use indexed snapshots with explicit freshness and finality labels."
        unavailableTitle="Analytics unavailable"
        unavailableDescription="Indexed snapshots are not connected. No sample metrics are presented."
      />
      <section className="workspace-panel" aria-labelledby="analytics-view-title">
        <div className="panel-head">
          <div>
            <p className="panel-kicker">View contract</p>
            <h2 id="analytics-view-title">Analytics views</h2>
          </div>
        </div>
        <Tabs
          ariaLabel="Analytics views"
          value={view}
          onChange={setView}
          tabs={[
            {
              value: "overview",
              label: "Overview",
              panel: <p>Overview will appear after indexed snapshots are connected.</p>,
            },
            {
              value: "definitions",
              label: "Definitions",
              panel: <p>Metric definitions will be published with the reviewed API contract.</p>,
            },
          ]}
        />
      </section>
    </>
  );
}
