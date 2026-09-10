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
  env: Record<string, string | undefined> = {
    NEXT_PUBLIC_E2E_FIXTURE: process.env.NEXT_PUBLIC_E2E_FIXTURE,
    NEXT_PUBLIC_TASK6_ANVIL_FACTORY: process.env.NEXT_PUBLIC_TASK6_ANVIL_FACTORY,
    NEXT_PUBLIC_TASK6_ANVIL_RPC_URL: process.env.NEXT_PUBLIC_TASK6_ANVIL_RPC_URL,
    NEXT_PUBLIC_PRIVY_APP_ID: process.env.NEXT_PUBLIC_PRIVY_APP_ID,
    NEXT_PUBLIC_DEPLOYMENT_ID: process.env.NEXT_PUBLIC_DEPLOYMENT_ID,
    NEXT_PUBLIC_CHAIN_ID: process.env.NEXT_PUBLIC_CHAIN_ID,
    NEXT_PUBLIC_API_BASE_URL: process.env.NEXT_PUBLIC_API_BASE_URL,
    NEXT_PUBLIC_RPC_URL: process.env.NEXT_PUBLIC_RPC_URL,
  },
): PublicConfiguration {
  if (env.NEXT_PUBLIC_E2E_FIXTURE === "1") {
    const factory = nonEmpty(env.NEXT_PUBLIC_TASK6_ANVIL_FACTORY);
    const fixtureRpc = publicEndpoint(nonEmpty(env.NEXT_PUBLIC_TASK6_ANVIL_RPC_URL));
    const rpcUrl = publicEndpoint("http://127.0.0.1:3000/e2e/rpc");
    if (factory && /^0x[0-9a-fA-F]{40}$/.test(factory) && fixtureRpc && rpcUrl) {
      return {
        status: "ready",
        privyAppId: "cl_e2e_fixture_1234567890",
        chainId: 31337,
        deploymentId: "task6-anvil",
        apiBaseUrl: "http://127.0.0.1:3000",
        rpcUrl,
        deployment: {
          deploymentId: "task6-anvil",
          chainId: 31337,
          name: "Anvil Task 6",
          enabled: true,
          factory,
          explorerBase: null,
          weth: "0x0000000000000000000000000000000000000001",
          uniswapV2Factory: null,
          uniswapV2Router02: null,
        } as (typeof reviewedDeployments)[number],
      };
    }
  }
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
