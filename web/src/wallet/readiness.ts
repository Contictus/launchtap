"use client";

import { usePrivy } from "@privy-io/react-auth";
import { useAccount, useChainId, useSwitchChain } from "wagmi";
import { publicConfiguration } from "@/config/public";

export type WalletReadinessStatus = "provider-loading" | "disconnected" | "wrong-chain" | "ready";

export type WalletReadiness = {
  status: WalletReadinessStatus;
  address: `0x${string}` | undefined;
  chainId: number | undefined;
  supportedChainId: number | null;
  authenticated: boolean;
  providerReady: boolean;
  switchNetwork: () => Promise<{ ok: true } | { ok: false; error: "switch-failed" }>;
};

export function getWalletStatus(args: {
  providerReady: boolean;
  address?: `0x${string}`;
  chainId?: number;
  supportedChainId: number | null;
}): WalletReadinessStatus {
  if (!args.providerReady) return "provider-loading";
  if (!args.address || !args.chainId) return "disconnected";
  return args.chainId === args.supportedChainId ? "ready" : "wrong-chain";
}

export async function switchToSupportedChain(
  chainId: number | null,
  switchChain: ((args: { chainId: number }) => Promise<unknown>) | undefined,
): Promise<{ ok: true } | { ok: false; error: "switch-failed" }> {
  if (!chainId || !switchChain) return { ok: false, error: "switch-failed" };
  try {
    await switchChain({ chainId });
    return { ok: true };
  } catch {
    return { ok: false, error: "switch-failed" };
  }
}

export function useWalletReadiness(): WalletReadiness {
  const configuration = publicConfiguration();
  const { ready: privyReady, authenticated } = usePrivy();
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { switchChainAsync } = useSwitchChain();
  const providerReady = privyReady;
  const status = getWalletStatus({
    providerReady,
    address: isConnected ? address : undefined,
    chainId: isConnected ? chainId : undefined,
    supportedChainId: configuration.chainId,
  });
  const switchNetwork = () => switchToSupportedChain(configuration.chainId, switchChainAsync);
  return {
    status,
    address: isConnected ? address : undefined,
    chainId: isConnected ? chainId : undefined,
    supportedChainId: configuration.chainId,
    authenticated,
    providerReady,
    switchNetwork,
  };
}
