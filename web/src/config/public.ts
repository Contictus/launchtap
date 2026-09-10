import { reviewedDeployments } from "@/contracts/generated";

export type PublicConfiguration = {
  status: "ready" | "fail-closed";
  privyAppId: string | null;
  chainId: number | null;
  deploymentId: string | null;
  apiBaseUrl: string | null;
  rpcUrl: string | null;
  deployment: (typeof reviewedDeployments)[number] | null;
};

const nonEmpty = (value: string | undefined) => (value?.trim() ? value.trim() : null);

function publicEndpoint(value: string | null): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    const local = url.hostname === "localhost" || url.hostname === "127.0.0.1";
    if (url.protocol !== "https:" && !(local && url.protocol === "http:")) return null;
    if (url.username || url.password || url.search || url.hash) return null;
    return url.toString().replace(/\/$/, "");
  } catch {
    return null;
  }
}

export function publicConfiguration(
  env: Record<string, string | undefined> = process.env,
): PublicConfiguration {
  const privyAppId = nonEmpty(env.NEXT_PUBLIC_PRIVY_APP_ID);
  const deploymentId = nonEmpty(env.NEXT_PUBLIC_DEPLOYMENT_ID);
  const chainValue = nonEmpty(env.NEXT_PUBLIC_CHAIN_ID);
  const parsedChainId = chainValue && /^\d+$/.test(chainValue) ? Number(chainValue) : NaN;
  const chainId = Number.isSafeInteger(parsedChainId) && parsedChainId > 0 ? parsedChainId : null;
  const apiBaseUrl = publicEndpoint(nonEmpty(env.NEXT_PUBLIC_API_BASE_URL));
  const rpcUrl = publicEndpoint(nonEmpty(env.NEXT_PUBLIC_RPC_URL));
  const deployment = reviewedDeployments.find(
    (candidate) => candidate.deploymentId === deploymentId && candidate.chainId === chainId,
  );
  const status =
    deployment?.enabled && privyAppId && apiBaseUrl && rpcUrl ? "ready" : "fail-closed";
  return {
    status,
    privyAppId,
    chainId,
    deploymentId,
    apiBaseUrl,
    rpcUrl,
    deployment: deployment ?? null,
  };
}
