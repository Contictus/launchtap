"use client";
/* Profile state follows authenticated external data and is reset on provider changes. */
/* eslint-disable react-hooks/set-state-in-effect */

import { useIdentityToken, usePrivy } from "@privy-io/react-auth";
import { useEffect, useState } from "react";
import { ApiClient, type ProfileResponse } from "@/api/client";
import { formatBaseUnits } from "@/amounts";
import { publicConfiguration } from "@/config/public";
import { Button, Badge, UnavailableState } from "@/components/primitives";
import { useWalletReadiness } from "@/wallet/readiness";
import { shortAddress } from "@/token/address";

type ProfileAction = NonNullable<ProfileResponse["items"]>[number];

export function ProfileView() {
  const configuration = publicConfiguration();
  const { authenticated, ready, user, login, logout, getAccessToken } = usePrivy();
  const { identityToken } = useIdentityToken();
  const readiness = useWalletReadiness();
  const [actions, setActions] = useState<ProfileAction[]>([]);
  const [actionsLoading, setActionsLoading] = useState(false);
  const [actionsError, setActionsError] = useState<string | null>(null);
  const email = user?.linkedAccounts?.find((item) => item.type === "email") as
    { address?: string } | undefined;
  const linked = readiness.linkedWallets;
  useEffect(() => {
    let cancelled = false;
    if (
      !authenticated ||
      !identityToken ||
      configuration.status !== "ready" ||
      !configuration.apiBaseUrl
    ) {
      setActions([]);
      setActionsError(null);
      return;
    }
    setActionsLoading(true);
    setActionsError(null);
    void getAccessToken()
      .then((accessToken) => {
        if (!accessToken) throw new Error("Access token unavailable");
        return new ApiClient({ baseUrl: configuration.apiBaseUrl! }).getProfile({
          accessToken,
          identityToken,
        });
      })
      .then((response) => {
        if (!cancelled) setActions(response.items ?? []);
      })
      .catch(() => {
        if (!cancelled) {
          setActions([]);
          setActionsError(
            "Authoritative claim availability is unavailable. Open a token detail page to retry.",
          );
        }
      })
      .finally(() => {
        if (!cancelled) setActionsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [
    authenticated,
    configuration.apiBaseUrl,
    configuration.status,
    getAccessToken,
    identityToken,
  ]);
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
          Availability comes from the authenticated API snapshot of canonical fee and refund events.
        </p>
        {actionsLoading ? <p role="status">Loading authoritative availability…</p> : null}
        {actionsError ? <p className="discovery-notice">{actionsError}</p> : null}
        {!actionsLoading && !actionsError && actions.length === 0 ? (
          <p>No creator fees or pending refunds are currently available for the linked wallets.</p>
        ) : null}
        {actions.length ? (
          <ul className="profile-action-list">
            {actions.map((action) => (
              <li key={action.token}>
                <div>
                  <a href={`/token/${action.token}`}>
                    {action.name || action.symbol || action.token}
                  </a>
                  <span className="ui-field-hint">{action.phase} · snapshot-bound</span>
                </div>
                <div className="mono profile-action-values">
                  <span>Creator fees: {formatEth(action.creator_fees)}</span>
                  <span>Refund: {formatEth(action.refund)}</span>
                </div>
              </li>
            ))}
          </ul>
        ) : null}
        {configuration.status !== "ready" || readiness.status !== "ready" ? (
          <p className="discovery-notice">
            Claims unavailable until a reviewed deployment and supported wallet are ready.
          </p>
        ) : null}
      </section>
    </div>
  );
}

function formatEth(value: string) {
  try {
    return `${formatBaseUnits(BigInt(value), 18, 6)} ETH`;
  } catch {
    return "Unavailable";
  }
}
