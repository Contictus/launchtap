import { ProfileView } from "@/profile/profile-view";
import { publicConfiguration } from "@/config/public";
import { UnavailableState } from "@/components/primitives";

export default function ProfilePage() {
  const configuration = publicConfiguration();
  return (
    <div className="page-stack">
      <section className="page-hero">
        <div>
          <h1>Your account.</h1>
          <p className="hero-summary">
            Review linked wallets, creator fees, and refunds without giving up custody.
          </p>
        </div>
      </section>
      {configuration.status === "ready" && configuration.privyAppId ? (
        <ProfileView />
      ) : (
        <UnavailableState
          title="Account unavailable"
          description="Account access is not configured for this environment. Public launch data remains available."
        />
      )}
    </div>
  );
}
