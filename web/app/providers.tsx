"use client";

import type { PropsWithChildren } from "react";

/**
 * Stable client boundary for app-wide providers. Wallet, query, and identity providers are
 * intentionally added in Plan 4 Task 3 once their public configuration is available.
 */
export function Providers({ children }: PropsWithChildren) {
  return children;
}
