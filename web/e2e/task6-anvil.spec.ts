import { expect, test, type Page } from "@playwright/test";

const sender = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" as const;

async function installWallet(page: Page) {
  await page.addInitScript(({ account }) => {
    let rejectNext = false;
    Object.defineProperty(window, "__task6RejectNext", {
      configurable: true,
      get: () => rejectNext,
      set: (value) => {
        rejectNext = Boolean(value);
      },
    });
    const listeners = new Map<string, Set<(...args: unknown[]) => void>>();
    Object.defineProperty(window, "ethereum", {
      configurable: true,
      value: {
        isMetaMask: false,
        on(event: string, listener: (...args: unknown[]) => void) {
          const set = listeners.get(event) ?? new Set();
          set.add(listener);
          listeners.set(event, set);
        },
        removeListener(event: string, listener: (...args: unknown[]) => void) {
          listeners.get(event)?.delete(listener);
        },
        request: async ({ method, params = [] }: { method: string; params?: unknown[] }) => {
          if (method === "eth_accounts" || method === "eth_requestAccounts") return [account];
          if (method === "wallet_requestPermissions") return [{ caveats: [] }];
          if (method === "wallet_getPermissions") return [];
          if (method === "wallet_switchEthereumChain") return null;
          if (method === "eth_chainId") return "0x7a69";
          if (method === "eth_sendTransaction" && rejectNext) {
            rejectNext = false;
            const error = new Error("User rejected the request");
            Object.assign(error, { code: 4001 });
            throw error;
          }
          const response = await fetch("/e2e/rpc", {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method, params }),
          });
          const body = (await response.json()) as {
            result?: unknown;
            error?: { message?: string; code?: number };
          };
          if (body.error) {
            const error = new Error(body.error.message ?? "RPC error");
            Object.assign(error, { code: body.error.code });
            throw error;
          }
          return body.result;
        },
      },
    });
  }, { account: sender });
}

test.describe("Task 6 Anvil transaction gate", () => {
  test.skip(
    !process.env.TASK6_ANVIL_RPC_URL || !process.env.TASK6_ANVIL_FACTORY,
    "Run web/scripts/anvil-task6-gate.ps1",
  );

  test("creates a token through the real create controls and reaches canonical observation", async ({ page }, testInfo) => {
    await installWallet(page);
    await page.goto("/create");
    await expect(page.getByRole("heading", { name: "Create a token" })).toBeVisible();
    await page.getByRole("button", { name: "Connect wallet" }).last().click();
    await page.getByLabel("Token name").fill("Browser Task 6");
    await page.getByLabel("Symbol").fill("B6");
    await page.getByRole("button", { name: "Review launch" }).click();
    await expect(page.getByRole("heading", { name: "Confirm launch" })).toBeVisible();
    await page.screenshot({
      path: `.impeccable/review/task6-create-confirm-${testInfo.project.name}.png`,
      fullPage: true,
    });
    await page.getByRole("button", { name: "Sign launch" }).click();
    await expect(page.getByRole("status")).toContainText(/finalized/i, { timeout: 30_000 });
    await expect(page.getByRole("status")).toContainText(/0x[0-9a-f]{64}/i);
  });

  test("keeps wallet rejection distinct while using the launch controls", async ({ page }) => {
    await installWallet(page);
    await page.goto("/create");
    await page.getByRole("button", { name: "Connect wallet" }).last().click();
    await page.getByLabel("Token name").fill("Rejected Task 6");
    await page.getByLabel("Symbol").fill("R6");
    await page.getByRole("button", { name: "Review launch" }).click();
    await page.evaluate(() => {
      (window as unknown as { __task6RejectNext: boolean }).__task6RejectNext = true;
    });
    await page.getByRole("button", { name: "Sign launch" }).click();
    await expect(page.getByRole("status")).toContainText(/rejected-signature/i, { timeout: 10_000 });
  });
});
