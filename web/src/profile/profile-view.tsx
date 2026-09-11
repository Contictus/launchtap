"use client";

import { usePrivy } from "@privy-io/react-auth";
import { publicConfiguration } from "@/config/public";
import { Button, Badge, UnavailableState } from "@/components/primitives";
import { useWalletReadiness } from "@/wallet/readiness";
import { shortAddress } from "@/token/address";

export function ProfileView() {
  const configuration = publicConfiguration();
  const { authenticated, ready, user, login, logout } = usePrivy();
  const readiness = useWalletReadiness();
  const email = user?.linkedAccounts?.find((item) => item.type === "email") as
    { address?: string } | undefined;
  const linked = readiness.linkedWallets;
  if (!ready)
    return (
      <UnavailableState
        title="Identity provider loading"
        description="Waiting for Privy to confirm the current identity."
      />
    );
  if (!authenticated) {
    return (
      <section className="workspace-panel profile-auth">
        <p className="panel-kicker">Identity</p>
        <h2>Sign in to see your profile</h2>
        <p>
          Launchpad does not create an account from a connected address. Privy is the source of
          identity and linked-wallet proof.
        </p>
        <Button variant="primary" onClick={() => login()}>
          Sign in with Privy
        </Button>
      </section>
    );
  }
  return (
    <div className="profile-layout">
      <section
        className="workspace-panel profile-identity"
        aria-labelledby="profile-identity-title"
      >
        <div className="panel-head">
          <div>
            <p className="panel-kicker">Authenticated identity</p>
            <h2 id="profile-identity-title">Your signing context</h2>
          </div>
          <Badge tone="success">Privy verified</Badge>
        </div>
        <dl className="profile-details">
          <div>
            <dt>Privy user</dt>
            <dd className="mono">{user?.id ?? "Unavailable"}</dd>
          </div>
          <div>
            <dt>Email</dt>
            <dd>{email?.address ?? "Not linked"}</dd>
          </div>
          <div>
            <dt>Selected network</dt>
            <dd>
              {readiness.status === "wrong-chain"
                ? "Wrong chain"
                : readiness.chainId
                  ? `Chain ${readiness.chainId}`
                  : "Disconnected"}
            </dd>
          </div>
        </dl>
        <Button variant="quiet" onClick={() => void logout()}>
          Sign out
        </Button>
      </section>
      <section className="workspace-panel" aria-labelledby="profile-wallets-title">
        <div className="panel-head">
          <div>
            <p className="panel-kicker">Wallet proof</p>
            <h2 id="profile-wallets-title">Linked wallets</h2>
          </div>
          <Badge tone={readiness.linkedWalletState === "linked" ? "success" : "warning"}>
            {readiness.linkedWalletState}
          </Badge>
        </div>
        {linked.length ? (
          <ul className="wallet-list">
            {linked.map((wallet) => (
              <li key={wallet.address}>
                <span className="mono">{shortAddress(wallet.address)}</span>
                <span>
                  {wallet.kind === "smart_wallet" ? "Smart wallet" : "Wallet"}
                  {wallet.address === readiness.address ? " · selected" : ""}
                </span>
              </li>
            ))}
          </ul>
        ) : (
          <p>No linked EVM wallet is available. Link one in Privy before creator actions.</p>
        )}
        <p className="ui-field-hint">
          A connected wallet is not automatically authorized as a token creator. The API verifies
          the linked wallet on each metadata write.
        </p>
      </section>
      <section className="workspace-panel profile-claims" aria-labelledby="profile-claims-title">
        <div className="panel-head">
          <div>
            <p className="panel-kicker">On-chain availability</p>
            <h2 id="profile-claims-title">Claims and refunds</h2>
          </div>
        </div>
        <p>
          Balances are read from the selected token contract at the moment you open its detail page.
          This profile has no invented aggregate balance.
        </p>
        <div className="claim-availability-grid">
          <div>
            <dt>Creator fees</dt>
            <dd>
              Open a token detail page to read <code>unclaimedCreatorFees</code>.
            </dd>
          </div>
          <div>
            <dt>Refund</dt>
            <dd>Open a token detail page to read the contract refund balance.</dd>
          </div>
        </div>
        {configuration.status !== "ready" || readiness.status !== "ready" ? (
          <p className="discovery-notice">
            Claims unavailable until a reviewed deployment and supported wallet are ready.
          </p>
        ) : null}
      </section>
    </div>
  );
}
