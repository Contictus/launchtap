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
    const factory = process.env.TASK6_ANVIL_FACTORY! as `0x${string}`;
    await page.addInitScript(() => {
      Object.defineProperty(window, "ethereum", {
        configurable: true,
        value: {
          request: async ({ method, params = [] }: { method: string; params?: unknown[] }) => {
            const response = await fetch("/e2e/rpc", {
              method: "POST",
              headers: { "content-type": "application/json" },
              body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method, params }),
            });
            const body = (await response.json()) as {
              result?: unknown;
              error?: { message?: string };
            };
            if (body.error) throw new Error(body.error.message ?? "RPC error");
            return body.result;
          },
        },
      });
    });
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
    const result = await page.evaluate(
      async ({ from, to, data }) => {
        const provider = (
          window as unknown as {
            ethereum: {
              request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
            };
          }
        ).ethereum;
        const chainId = (await provider.request({ method: "eth_chainId" })) as string;
        const hash = (await provider.request({
          method: "eth_sendTransaction",
          params: [{ from, to, data, value: "0x0" }],
        })) as string;
        for (let attempt = 0; attempt < 50; attempt++) {
          const receipt = (await provider.request({
            method: "eth_getTransactionReceipt",
            params: [hash],
          })) as { status?: string } | null;
          if (receipt) return { chainId, hash, receipt };
          await new Promise((resolve) => setTimeout(resolve, 100));
        }
        throw new Error("Receipt timeout");
      },
      { from: sender, to: factory, data: launchData },
    );
    expect(result.chainId).toBe("0x7a69");
    expect(result.hash).toMatch(/^0x[0-9a-f]{64}$/);
    expect(result.receipt.status).toBe("0x1");
  });
});
