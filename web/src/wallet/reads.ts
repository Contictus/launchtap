import type { PublicClient, Address } from "viem";
import { browserAbis } from "@/contracts/generated";

export type WalletReadClient = Pick<PublicClient, "getBalance" | "readContract">;

export function readNativeBalance(client: WalletReadClient, address: Address) {
  return client.getBalance({ address });
}

export function readTokenBalance(client: WalletReadClient, token: Address, account: Address) {
  return client.readContract({
    address: token,
    abi: browserAbis.token,
    functionName: "balanceOf",
    args: [account],
  });
}

export function readTokenAllowance(
  client: WalletReadClient,
  token: Address,
  owner: Address,
  spender: Address,
) {
  return client.readContract({
    address: token,
    abi: browserAbis.token,
    functionName: "allowance",
    args: [owner, spender],
  });
}
