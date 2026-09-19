import { Suspense } from "react";
import { TokenDiscovery } from "./token-discovery";

export function ExploreHub() {
  return (
    <div className="page-stack explore-hub">
      <section className="explore-intro" aria-labelledby="explore-title">
        <p className="section-kicker">Explore</p>
        <h1 id="explore-title">Discover the next launch.</h1>
        <p>
          Browse tokens by where they are in the route. Images, names, and market context come
          first; the mechanics stay out of the way.
        </p>
      </section>
      <Suspense fallback={<ExploreFallback label="Loading graduated tokens…" />}>
        <TokenDiscovery
          defaultPhase="graduated"
          fixedPhase="graduated"
          showHero={false}
          showSearch
          showSortControls
          title="Graduated"
          summary="Tokens that cleared the graduation threshold."
        />
      </Suspense>
      <Suspense fallback={<ExploreFallback label="Loading all tokens…" />}>
        <TokenDiscovery
          defaultPhase="curve"
          fixedPhase="curve"
          showHero={false}
          showSearch={false}
          showSortControls
          title="Explore"
          summary="New launches and tokens still moving toward graduation."
        />
      </Suspense>
    </div>
  );
}

function ExploreFallback({ label }: { label: string }) {
  return (
    <section className="workspace-panel explore-fallback" aria-busy="true">
      <p className="mono">{label}</p>
    </section>
  );
}
