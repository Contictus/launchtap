import { publicConfiguration } from "@/config/public";

export default function HomePage() {
  const configuration = publicConfiguration();
  return (
    <main className="diagnostic-shell">
      <p className="eyebrow">Launchpad / infrastructure</p>
      <h1>Web boundary is ready.</h1>
      <p className="summary">
        Product routes are intentionally not enabled in Plan 4 Task 1. Configuration remains
        fail-closed until a reviewed launchpad deployment and public runtime values exist.
      </p>
      <dl className="diagnostics" aria-label="Runtime configuration">
        <div>
          <dt>Deployment</dt>
          <dd>{configuration.deploymentId ?? "not configured"}</dd>
        </div>
        <div>
          <dt>Chain</dt>
          <dd>{configuration.chainId ?? "not configured"}</dd>
        </div>
        <div>
          <dt>Status</dt>
          <dd>{configuration.status}</dd>
        </div>
      </dl>
    </main>
  );
}
