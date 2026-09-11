import { Suspense } from "react";
import { TokenDiscovery } from "@/discovery/token-discovery";

export default function GraduatedPage() {
  return (
    <Suspense fallback={<DiscoveryFallback />}>
      <TokenDiscovery
        defaultPhase="graduated"
        title="Graduated routes."
        summary="Review completed launch routes from the canonical indexed snapshot."
      />
    </Suspense>
  );
}

function DiscoveryFallback() {
  return (
    <div className="page-stack discovery-page" aria-busy="true">
      <div className="discovery-state">
        <p className="mono">Loading graduated routes…</p>
      </div>
    </div>
  );
}
