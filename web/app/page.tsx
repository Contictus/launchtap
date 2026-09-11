import { Suspense } from "react";
import { TokenDiscovery } from "@/discovery/token-discovery";

export default function HomePage() {
  return (
    <Suspense fallback={<DiscoveryFallback />}>
      <TokenDiscovery
        title="Explore the launch route."
        summary="Inspect indexed tokens, follow each lifecycle state, and sign only when the route is clear."
      />
    </Suspense>
  );
}

function DiscoveryFallback() {
  return (
    <div className="page-stack discovery-page" aria-busy="true">
      <div className="discovery-state">
        <p className="mono">Loading indexed routes…</p>
      </div>
    </div>
  );
}
