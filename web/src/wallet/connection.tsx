"use client";

import { createContext, useContext, useMemo, type PropsWithChildren } from "react";
import { useAccount, useConnect } from "wagmi";
import { Wallet } from "@/components/icons";
import { Button } from "@/components/primitives";

type WalletConnection = {
  connect: () => void;
  connected: boolean;
  pending: boolean;
  address?: string;
};

const fallbackConnection: WalletConnection = {
  connect: () => {
    const provider = (window as Window & { ethereum?: { request: (args: { method: string }) => Promise<unknown> } }).ethereum;
    if (provider) void provider.request({ method: "eth_requestAccounts" });
  },
  connected: false,
  pending: false,
};

const WalletConnectionContext = createContext<WalletConnection>(fallbackConnection);

export function WalletConnectionBridge({ children }: PropsWithChildren) {
  const { connect, connectors, isPending } = useConnect();
  const { address, isConnected } = useAccount();
  const value = useMemo<WalletConnection>(
    () => ({
      connect: () => {
        const connector = connectors[0];
        if (connector) connect({ connector });
      },
      connected: isConnected,
      pending: isPending,
      address,
    }),
    [address, connect, connectors, isConnected, isPending],
  );
  return <WalletConnectionContext.Provider value={value}>{children}</WalletConnectionContext.Provider>;
}

export function WalletConnectButton({ className }: { className?: string } = {}) {
  const wallet = useContext(WalletConnectionContext);
  const label = wallet.pending
    ? "Connecting wallet"
    : wallet.connected
      ? "Wallet connected"
      : "Connect wallet";
  return (
    <Button
      variant="quiet"
      size="sm"
      onClick={wallet.connect}
      className={className ?? "navbar-wallet"}
      aria-label={label}
      title={label}
    >
      <Wallet size={17} /> <span>{label}</span>
    </Button>
  );
}
