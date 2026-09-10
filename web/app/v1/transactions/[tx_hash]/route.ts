import { parseEventLogs } from "viem";
import { browserAbis } from "@/contracts/generated";

type RpcReceipt = {
  status?: string;
  blockNumber?: string;
  blockHash?: string;
  logs?: Array<{ address: string; topics: string[]; data: string }>;
};

async function rpc(method: string, params: unknown[]) {
  const endpoint = process.env.TASK6_ANVIL_RPC_URL ?? process.env.NEXT_PUBLIC_TASK6_ANVIL_RPC_URL;
  if (process.env.NEXT_PUBLIC_E2E_FIXTURE !== "1" || !endpoint)
    throw new Error("fixture disabled");
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method, params }),
    cache: "no-store",
  });
  const body = (await response.json()) as { result?: unknown; error?: { message?: string } };
  if (body.error) throw new Error(body.error.message ?? "RPC error");
  return body.result;
}

export async function GET(_: Request, context: { params: Promise<{ tx_hash: string }> }) {
  const { tx_hash: hash } = await context.params;
  if (process.env.NEXT_PUBLIC_E2E_FIXTURE !== "1" || !/^0x[0-9a-fA-F]{64}$/.test(hash))
    return Response.json({ detail: "Not found" }, { status: 404 });
  const receipt = (await rpc("eth_getTransactionReceipt", [hash])) as RpcReceipt | null;
  if (!receipt || receipt.status !== "0x1" || !receipt.blockNumber || !receipt.blockHash)
    return Response.json({ detail: "Transaction has no canonical indexed event" }, { status: 404 });
  let kind = "trade";
  let token: string | undefined;
  const launch = parseEventLogs({
    abi: browserAbis.factory,
    eventName: "TokenLaunched",
    logs: (receipt.logs ?? []) as never,
    strict: false,
  }).find((event) => typeof event.args.token === "string");
  if (launch && typeof launch.args.token === "string") {
    kind = "token_launch";
    token = launch.args.token;
  }
  const blockNumber = Number.parseInt(receipt.blockNumber, 16);
  return Response.json({
    chain_id: 31337,
    deployment_id: "task6-anvil",
    tx_hash: hash,
    snapshot: { chain_id: 31337, as_of_block: blockNumber, as_of_block_hash: receipt.blockHash, finality: "finalized" },
    finality: "finalized",
    events: [{ kind, tx_hash: hash, ...(token ? { token } : {}), block_number: blockNumber, block_hash: receipt.blockHash, block_time: new Date().toISOString(), transaction_index: 0, log_index: 0, finality: "finalized" }],
  });
}
