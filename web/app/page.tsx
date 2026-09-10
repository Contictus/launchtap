import { publicConfiguration } from "@/config/public";
import {
  Badge,
  EmptyState,
  SafeExternalLink,
  TransactionStatus,
  UnavailableState,
} from "@/components/primitives";
import { ArrowSquareOut, Compass, ShieldCheck } from "@/components/icons";

export default function HomePage() {
  const configuration = publicConfiguration();
  return (
    <div className="page-stack">
      <section className="page-hero" aria-labelledby="explore-title">
        <div>
          <div className="section-kicker">
            <Compass size={14} /> Discovery
          </div>
          <h1 id="explore-title">Explore the launch route.</h1>
          <p className="hero-summary">
            Inspect indexed tokens, follow each lifecycle state, and sign only when the route is
            clear.
          </p>
        </div>
        <div className="hero-aside">
          <span className="hero-rule" />
          <p>
            A fixed-supply token moves from launch to curve trading, then into graduated liquidity.
            The browser never takes custody.
          </p>
          <Badge tone="warning">Read-only shell</Badge>
        </div>
      </section>
      <section className="workspace-panel" aria-labelledby="lifecycle-title">
        <div className="panel-head">
          <div>
            <p className="panel-kicker">Launch route</p>
            <h2 id="lifecycle-title">Lifecycle ledger</h2>
          </div>
          <TransactionStatus status="stale" />
        </div>
        <div className="workspace-grid">
          <ol className="lifecycle-list" aria-label="Token lifecycle">
            <li className="is-current">
              <span className="lifecycle-node">01</span>
              <div>
                <strong>Launch</strong>
                <p>Creator submits a fixed-supply token.</p>
              </div>
            </li>
            <li>
              <span className="lifecycle-node">02</span>
              <div>
                <strong>Curve</strong>
                <p>Participants trade against the bonding curve.</p>
              </div>
            </li>
            <li>
              <span className="lifecycle-node">03</span>
              <div>
                <strong>Graduation</strong>
                <p>Liquidity routes to the reviewed V2 pool.</p>
              </div>
            </li>
            <li>
              <span className="lifecycle-node">04</span>
              <div>
                <strong>Liquidity</strong>
                <p>Initial LP position is burned.</p>
              </div>
            </li>
          </ol>
          <div className="ledger-empty">
            <EmptyState
              title="No indexed tokens yet"
              description="The API is not connected, so discovery remains empty instead of showing sample market data."
            />
          </div>
        </div>
      </section>
      <section className="trust-strip" aria-label="Runtime status">
        <div>
          <ShieldCheck size={20} />
          <div>
            <strong>Non-custodial by design</strong>
            <p>You select the wallet, review the contract call, and sign every write.</p>
          </div>
        </div>
        <dl className="runtime-list">
          <div>
            <dt>Deployment</dt>
            <dd>{configuration.deploymentId ?? "Not configured"}</dd>
          </div>
          <div>
            <dt>Chain</dt>
            <dd>{configuration.chainId ?? "Not configured"}</dd>
          </div>
          <div>
            <dt>API state</dt>
            <dd>
              <Badge tone={configuration.status === "ready" ? "success" : "warning"}>
                {configuration.status === "ready" ? "Ready" : "Fail-closed"}
              </Badge>
            </dd>
          </div>
        </dl>
      </section>
      <UnavailableState
        title="Indexed discovery unavailable"
        description="Connect a reviewed API and deployment to load current tokens. Cached values are not presented as current."
      />
      <p className="source-note">
        This shell is ready for Plan 4 data foundations.{" "}
        <SafeExternalLink href="https://robinhoodchain.blockscout.com">
          View the public explorer <ArrowSquareOut size={13} />
        </SafeExternalLink>
      </p>
    </div>
  );
}
