"use client";

import { useConnectWallet } from "@privy-io/react-auth";
import { createContext, useContext, useMemo, useState, type PropsWithChildren } from "react";
import { useAccount, useConnect, useDisconnect } from "wagmi";
import { Wallet } from "@/components/icons";
import { Button, Dialog, type ButtonProps } from "@/components/primitives";
import { shortAddress } from "@/token/address";

type WalletConnection = {
  open: () => void;
  disconnect: () => void;
  connected: boolean;
  pending: boolean;
  available: boolean;
  address?: string;
};

const fallbackConnection: WalletConnection = {
  open: () => undefined,
  disconnect: () => undefined,
  connected: false,
  pending: false,
  available: false,
};

const WalletConnectionContext = createContext<WalletConnection>(fallbackConnection);

export function useWalletConnection() {
  return useContext(WalletConnectionContext);
}

export function WagmiWalletConnectionBridge({ children }: PropsWithChildren) {
  const { connect, connectors, error, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { address, isConnected } = useAccount();
  const [open, setOpen] = useState(false);
  const value = useMemo<WalletConnection>(
    () => ({
      open: () => setOpen(true),
      disconnect: () => disconnect(),
      connected: isConnected,
      pending: isPending,
      available: connectors.length > 0,
      address,
    }),
    [address, connectors.length, disconnect, isConnected, isPending],
  );

  return (
    <WalletConnectionContext.Provider value={value}>
      {children}
      <Dialog
        open={open}
        title={isConnected ? "Wallet connection" : "Choose a wallet"}
        description="Select the wallet that will submit and sign your transactions."
        onClose={() => setOpen(false)}
      >
        <div className="wallet-picker">
          {isConnected && address ? (
            <div className="wallet-picker-current">
              <span>Connected wallet</span>
              <strong className="mono">{shortAddress(address)}</strong>
            </div>
          ) : null}
          <div className="wallet-picker-list" aria-label="Available wallets">
            {connectors.map((connector) => (
              <Button
                key={connector.uid}
                variant="secondary"
                loading={isPending}
                onClick={() =>
                  connect(
                    { connector },
                    {
                      onSuccess: () => setOpen(false),
                    },
                  )
                }
              >
                <Wallet size={18} aria-hidden="true" />
                {walletConnectorLabel(connector.name)}
              </Button>
            ))}
          </div>
          {connectors.length === 0 ? (
            <p className="wallet-picker-error" role="status">
              No compatible browser wallet was detected.
            </p>
          ) : null}
          {error ? (
            <p className="wallet-picker-error" role="alert">
              The wallet did not connect. Choose a wallet and try again.
            </p>
          ) : null}
          {isConnected ? (
            <Button
              variant="quiet"
              onClick={() => {
                disconnect();
                setOpen(false);
              }}
            >
              Disconnect
            </Button>
          ) : null}
        </div>
      </Dialog>
    </WalletConnectionContext.Provider>
  );
}

export function PrivyWalletConnectionBridge({ children }: PropsWithChildren) {
  const { connectWallet } = useConnectWallet();
  const { disconnect } = useDisconnect();
  const { address, isConnected } = useAccount();
  const value = useMemo<WalletConnection>(
    () => ({
      open: () => connectWallet(),
      disconnect: () => disconnect(),
      connected: isConnected,
      pending: false,
      available: true,
      address,
    }),
    [address, connectWallet, disconnect, isConnected],
  );
  return (
    <WalletConnectionContext.Provider value={value}>{children}</WalletConnectionContext.Provider>
  );
}

export function walletConnectorLabel(name: string) {
  const label = name.trim();
  if (!label || /^injected$/i.test(label)) return "Browser wallet";
  return label;
}

export function WalletConnectButton({
  className,
  variant = "quiet",
  size = "sm",
}: {
  className?: string;
  variant?: ButtonProps["variant"];
  size?: ButtonProps["size"];
} = {}) {
  const wallet = useWalletConnection();
  const label = wallet.pending
    ? "Connecting wallet"
    : wallet.connected && wallet.address
      ? shortAddress(wallet.address)
      : wallet.available
        ? "Connect wallet"
        : "Wallet unavailable";
  return (
    <Button
      variant={variant}
      size={size}
      onClick={wallet.open}
      disabled={!wallet.available}
      loading={wallet.pending}
      className={className ?? "navbar-wallet"}
      aria-label={label}
      title={label}
    >
      <Wallet size={17} aria-hidden="true" /> <span>{label}</span>
    </Button>
  );
}
