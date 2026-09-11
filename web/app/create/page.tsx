import { LaunchPanel } from "@/transactions-panel";

export default function CreatePage() {
  return (
    <div className="page-stack create-page">
      <div className="page-hero">
        <div>
          <p className="section-kicker">Create</p>
          <h1>Launch a fixed-supply token.</h1>
          <p className="hero-summary">
            Review the factory state, exact launch value, and wallet call before signing.
          </p>
        </div>
        <p className="hero-aside">
          Non-custodial by design. Missing reviewed deployment configuration keeps launch
          unavailable.
        </p>
      </div>
      <LaunchPanel />
    </div>
  );
}
