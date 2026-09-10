"use client";

import { PrivyProvider } from "@privy-io/react-auth";
import { WagmiProvider } from "@privy-io/wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState, type PropsWithChildren } from "react";
import { publicConfiguration } from "@/config/public";
import { createWeb3Config } from "@/wallet/config";

/**
 * Stable client boundary for app-wide providers. Wallet, query, and identity providers are
 * intentionally added in Plan 4 Task 3 once their public configuration is available.
 */
export function Providers({ children }: PropsWithChildren) {
  const configuration = publicConfiguration();
  const web3 = createWeb3Config(configuration);
  const [queryClient] = useState(() => new QueryClient());

  // Deliberately render the read-only shell without wallet providers when any public value is
  // missing. This prevents a partially configured client from making auth or transaction claims.
  if (!web3 || !configuration.privyAppId) return children;
  return (
    <PrivyProvider appId={configuration.privyAppId}>
      <QueryClientProvider client={queryClient}>
        <WagmiProvider config={web3.config}>{children}</WagmiProvider>
      </QueryClientProvider>
    </PrivyProvider>
  );
}
