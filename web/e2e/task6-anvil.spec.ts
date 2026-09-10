import { expect, test } from "@playwright/test";
import { encodeFunctionData } from "viem";
import { browserAbis } from "../src/contracts/generated";

const sender = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" as const;

test.describe("Task 6 Anvil transaction gate", () => {
  test.skip(
    !process.env.TASK6_ANVIL_RPC_URL || !process.env.TASK6_ANVIL_FACTORY,
    "Run web/scripts/anvil-task6-gate.ps1",
  );

  test("browser harness performs an authoritative launch write and receipt check", async ({
    page,
  }) => {
    const rpc = process.env.TASK6_ANVIL_RPC_URL!;
    const factory = process.env.TASK6_ANVIL_FACTORY! as `0x${string}`;
    await page.goto("/");
    const launchData = encodeFunctionData({
      abi: browserAbis.factory,
      functionName: "launch",
      args: [
        {
          name: "Browser Task 6",
          symbol: "B6",
          engineVersion: 1,
          developerBuyGross: 0n,
          minDeveloperTokensOut: 0n,
          deadline: 9_999_999_999n,
        },
      ],
    });
    const call = async (method: string, params: unknown[]) => {
      const response = await page.request.post(rpc, {
        data: { jsonrpc: "2.0", id: Date.now(), method, params },
      });
      const body = (await response.json()) as { result?: unknown; error?: { message?: string } };
      if (body.error) throw new Error(body.error.message ?? "RPC error");
      return body.result!;
    };
    const chainId = await call("eth_chainId", []);
    const hash = await call("eth_sendTransaction", [
      {
        from: sender,
        to: factory,
        data: launchData,
        value: "0x0",
      },
    ]);
    let receipt: { status?: string } | undefined;
    for (let attempt = 0; attempt < 50; attempt++) {
      receipt = (await call("eth_getTransactionReceipt", [hash])) as { status?: string };
      if (receipt) break;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    if (!receipt) throw new Error("Receipt timeout");
    expect(chainId).toBe("0x7a69");
    expect(hash).toMatch(/^0x[0-9a-f]{64}$/);
    expect(receipt.status).toBe("0x1");
  });
});
