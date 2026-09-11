import { ProfileView } from "@/profile/profile-view";
import { publicConfiguration } from "@/config/public";
import { UnavailableState } from "@/components/primitives";

export default function ProfilePage() {
  const configuration = publicConfiguration();
  return (
    <div className="page-stack">
      <section className="page-hero">
        <div>
          <div className="section-kicker">Profile</div>
          <h1>Your signing context.</h1>
          <p className="hero-summary">
            Identity and linked wallets remain user-controlled. Creator authorization stays on the
            server and claim balances stay on-chain.
          </p>
        </div>
      </section>
      {configuration.status === "ready" && configuration.privyAppId ? (
        <ProfileView />
      ) : (
        <UnavailableState
          title="Profile unavailable"
          description="Privy and a reviewed public deployment are not configured. No account is inferred from a wallet address."
        />
      )}
    </div>
  );
}
