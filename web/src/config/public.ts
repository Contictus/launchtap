import { reviewedDeployments } from "@/contracts/generated";

export type PublicConfiguration = {
  status: "ready" | "fail-closed";
  chainId: number | null;
  deploymentId: string | null;
  apiBaseUrl: string | null;
  rpcUrl: string | null;
};

const nonEmpty = (value: string | undefined) => (value?.trim() ? value.trim() : null);

export function publicConfiguration(
  env: Record<string, string | undefined> = process.env,
): PublicConfiguration {
  const deploymentId = nonEmpty(env.NEXT_PUBLIC_DEPLOYMENT_ID);
  const chainValue = nonEmpty(env.NEXT_PUBLIC_CHAIN_ID);
  const chainId = chainValue && /^\d+$/.test(chainValue) ? Number(chainValue) : null;
  const apiBaseUrl = nonEmpty(env.NEXT_PUBLIC_API_BASE_URL);
  const rpcUrl = nonEmpty(env.NEXT_PUBLIC_RPC_URL);
  const deployment = reviewedDeployments.find(
    (candidate) => candidate.deploymentId === deploymentId && candidate.chainId === chainId,
  );
  const status = deployment?.enabled && apiBaseUrl && rpcUrl ? "ready" : "fail-closed";
  return { status, chainId, deploymentId, apiBaseUrl, rpcUrl };
}
