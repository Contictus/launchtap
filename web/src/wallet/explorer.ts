import type { Address, Hash } from "viem";
import type { PublicConfiguration } from "@/config/public";

function explorerUrl(base: string | null, path: string): string | null {
  if (!base) return null;
  try {
    const url = new URL(`${base.replace(/\/$/, "")}/${path}`);
    return url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
}

export function transactionExplorerUrl(
  configuration: PublicConfiguration,
  hash: Hash,
): string | null {
  return explorerUrl(configuration.deployment?.explorerBase ?? null, `tx/${hash}`);
}

export function addressExplorerUrl(
  configuration: PublicConfiguration,
  address: Address,
): string | null {
  return explorerUrl(configuration.deployment?.explorerBase ?? null, `address/${address}`);
}
