import { expect, test, type Page } from "@playwright/test";
import fs from "node:fs";
import path from "node:path";

const sender = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" as const;

async function installWallet(page: Page, initialChainId = "0x7a69") {
  await page.addInitScript(
    ({ account, initialChainId }) => {
      let rejectNext = false;
      let chainId = initialChainId;
      Object.defineProperty(window, "__task6RejectNext", {
        configurable: true,
        get: () => rejectNext,
        set: (value) => {
          rejectNext = Boolean(value);
        },
      });
      Object.defineProperty(window, "__task6ChainId", {
        configurable: true,
        get: () => chainId,
        set: (value) => {
          chainId = String(value);
          for (const listener of listeners.get("chainChanged") ?? []) listener(chainId);
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
            if (method === "wallet_switchEthereumChain") {
              chainId = "0x7a69";
              for (const listener of listeners.get("chainChanged") ?? []) listener(chainId);
              return null;
            }
            if (method === "eth_chainId") return chainId;
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
              error?: { message?: string; code?: number; data?: unknown };
            };
            if (body.error) {
              const error = new Error(
                `${body.error.message ?? "RPC error"} ${JSON.stringify(body.error)}`,
              );
              Object.assign(error, body.error);
              throw error;
            }
            return body.result;
          },
        },
      });
    },
    { account: sender, initialChainId },
  );
}

async function canonicalTokenForLaunch(page: Page, api: string, hash: string, name: string) {
  const response = await page.request.get(`${api}/v1/transactions/${hash}`);
  if (response.ok()) {
    const body = (await response.json()) as { events?: { kind: string; token?: string }[] };
    const eventToken = body.events?.find((event) => event.kind === "token_launch")?.token;
    if (eventToken) return eventToken;
  }
  const tokens = await page.request.get(
    `${api}/v1/tokens?phase=curve&q=${encodeURIComponent(name)}`,
  );
  if (!tokens.ok()) return "";
  const body = (await tokens.json()) as { items?: { name: string; address: string }[] };
  return body.items?.find((item) => item.name === name)?.address ?? "";
}

test.describe("Task 6 Anvil transaction gate", () => {
  const configured = Boolean(
    process.env.TASK6_ANVIL_RPC_URL &&
    process.env.TASK6_ANVIL_FACTORY &&
    process.env.TASK6_ANVIL_WETH &&
    process.env.TASK6_ANVIL_ROUTER &&
    process.env.TASK6_ANVIL_UNISWAP_FACTORY &&
    process.env.TASK6_ANVIL_API_URL,
  );
  test.beforeAll(() => {
    if (
      process.env.TASK6_ANVIL_REQUIRED === "1" &&
      (!process.env.TASK6_ANVIL_RPC_URL ||
        !process.env.TASK6_ANVIL_FACTORY ||
        !process.env.TASK6_ANVIL_WETH ||
        !process.env.TASK6_ANVIL_ROUTER ||
        !process.env.TASK6_ANVIL_UNISWAP_FACTORY ||
        !process.env.TASK6_ANVIL_API_URL)
    )
      throw new Error(
        "Task 6 Anvil gate requires the real RPC, API, factory, WETH, router, and pair factory configuration",
      );
  });
  test.beforeEach(({}, testInfo) => {
    if (!configured) testInfo.skip(true, "Run through the real Task 6 Anvil gate");
  });

  test("creates a token through the real create controls and reaches canonical observation", async ({
    page,
  }, testInfo) => {
    await installWallet(page);
    await page.goto("/create");
    await expect(page.getByRole("heading", { name: "Create a token" })).toBeVisible();
    await page.getByRole("button", { name: "Connect wallet" }).last().click();
    await page.getByLabel("Token name").fill("Browser Task 6");
    await page.getByLabel("Symbol").fill("B6");
    await page.getByRole("button", { name: "Review launch" }).click();
    await expect(page.getByRole("heading", { name: "Confirm launch" })).toBeVisible();
    const evidenceDir = path.resolve(process.cwd(), "..", ".impeccable", "review");
    fs.mkdirSync(evidenceDir, { recursive: true });
    await page.screenshot({
      path: path.join(evidenceDir, `task6-create-confirm-${testInfo.project.name}.png`),
      fullPage: true,
    });
    await page.getByRole("button", { name: "Sign launch" }).click();
    const status = page.getByRole("status");
    await expect(status).toContainText(/indexing|indexed|safe|finalized/i, { timeout: 30_000 });
    const hash = (await status.textContent())?.match(/0x[0-9a-f]{64}/i)?.[0];
    expect(hash).toBeTruthy();
    await expect
      .poll(
        async () =>
          (
            await page.request.get(`${process.env.TASK6_ANVIL_API_URL}/v1/transactions/${hash}`)
          ).status(),
        { timeout: 30_000 },
      )
      .toBe(200);
  });

  test("buys and sells through curve controls with a separate approval transaction", async ({
    page,
  }, testInfo) => {
    await installWallet(page);
    await page.goto("/create");
    await page.getByRole("button", { name: "Connect wallet" }).last().click();
    await page.getByLabel("Token name").fill("Browser Trade Task 6");
    await page.getByLabel("Symbol").fill("BT6");
    await page.getByRole("button", { name: "Review launch" }).click();
    await page.getByRole("button", { name: "Sign launch" }).click();
    const launchStatus = page.getByRole("status").last();
    await expect(launchStatus).toContainText(/indexing|indexed|safe|finalized/i, {
      timeout: 30_000,
    });
    const launchHash = (await launchStatus.textContent())?.match(/0x[0-9a-f]{64}/i)?.[0];
    expect(launchHash).toBeTruthy();
    const api = process.env.TASK6_ANVIL_API_URL!;
    let tokenAddress = "";
    await expect
      .poll(
        async () => {
          tokenAddress = await canonicalTokenForLaunch(
            page,
            api,
            launchHash!,
            "Browser Trade Task 6",
          );
          return tokenAddress;
        },
        { timeout: 30_000 },
      )
      .toMatch(/^0x[0-9a-f]{40}$/i);
    await page.goto(`/token/${tokenAddress}`);
    await expect(page.getByRole("heading", { name: "Browser Trade Task 6" })).toBeVisible({
      timeout: 30_000,
    });
    await page.getByLabel("ETH input").fill("0.001");
    await page.getByRole("button", { name: "Review buy" }).click();
    const evidenceDir = path.resolve(process.cwd(), "..", ".impeccable", "review");
    fs.mkdirSync(evidenceDir, { recursive: true });
    await page.screenshot({
      path: path.join(evidenceDir, `task6-trade-confirm-${testInfo.project.name}.png`),
      fullPage: true,
    });
    await page.getByRole("button", { name: "Sign buy" }).click();
    await expect(page.getByRole("status").last()).toContainText(
      /indexing|indexed|safe|finalized/i,
      { timeout: 30_000 },
    );

    await page.reload();
    await page.getByRole("tab", { name: "Sell" }).click();
    await page.getByLabel(/BT6 input/).fill("1");
    await page.getByRole("button", { name: "Review sell" }).click();
    await page.getByRole("button", { name: "Sign sell" }).click();
    await expect(page.getByRole("status").last()).toContainText(
      /mined|indexing|indexed|safe|finalized/i,
      {
        timeout: 30_000,
      },
    );
    await page.getByRole("button", { name: "Resume sell" }).click();
    await page.screenshot({
      path: path.join(evidenceDir, `task6-approval-confirm-${testInfo.project.name}.png`),
      fullPage: true,
    });
    await page.getByRole("button", { name: "Sign sell" }).click();
    await expect(page.getByRole("status").last()).toContainText(/indexed|safe|finalized/i, {
      timeout: 30_000,
    });
  });

  test("switches from a wrong chain before signing", async ({ page }) => {
    await installWallet(page, "0x1");
    await page.goto("/create");
    await page.getByRole("button", { name: "Connect wallet" }).last().click();
    await expect(page.getByText(/Wrong network/i)).toBeVisible();
    await page.getByRole("button", { name: "Switch network" }).click();
    await expect(page.getByText(/Wrong network/i)).toHaveCount(0);
    await page.getByLabel("Token name").fill("Wrong Chain Task 6");
    await page.getByLabel("Symbol").fill("WC6");
    await page.getByRole("button", { name: "Review launch" }).click();
    await page.evaluate(() => {
      (window as unknown as { __task6ChainId: string }).__task6ChainId = "0x1";
    });
    await page.waitForTimeout(250);
    await expect(page.getByText(/Wrong network/i)).toBeVisible();
    await page.getByRole("button", { name: "Switch network" }).click();
    await expect(page.getByText(/Wrong network/i)).toHaveCount(0);
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
    await expect(page.getByRole("status")).toContainText(/rejected-signature/i, {
      timeout: 10_000,
    });
  });

  test("surfaces a decoded contract cap revert from the real launch controls", async ({ page }) => {
    await installWallet(page);
    await page.goto("/create");
    await page.getByRole("button", { name: "Connect wallet" }).last().click();
    await page.getByLabel("Token name").fill("Revert Task 6");
    await page.getByLabel("Symbol").fill("RV6");
    await page.getByLabel("Developer buy (ETH, optional)").fill("0.02");
    await page.getByRole("button", { name: "Review launch" }).click();
    await page.getByRole("button", { name: "Sign launch" }).click();
    await expect(page.locator(".transaction-error")).toContainText(
      /developer buy exceeds the contract cap/i,
      { timeout: 15_000 },
    );
    await expect(page.getByRole("status")).toContainText(/simulation-reverted/i);
  });

  test("uses the reviewed graduated router for wrong-chain, buy, approval, and sell", async ({
    page,
  }, testInfo) => {
    await installWallet(page);
    await page.goto("/create");
    await page.getByRole("button", { name: "Connect wallet" }).last().click();
    await page.getByLabel("Token name").fill("Graduated Task 6");
    await page.getByLabel("Symbol").fill("GR6");
    await page.getByRole("button", { name: "Review launch" }).click();
    await page.getByRole("button", { name: "Sign launch" }).click();
    const launchStatus = page.getByRole("status").last();
    await expect(launchStatus).toContainText(/indexing|indexed|safe|finalized/i, {
      timeout: 30_000,
    });
    const launchHash = (await launchStatus.textContent())?.match(/0x[0-9a-f]{64}/i)?.[0];
    expect(launchHash).toBeTruthy();
    const api = process.env.TASK6_ANVIL_API_URL!;
    let tokenAddress = "";
    await expect
      .poll(
        async () => {
          tokenAddress = await canonicalTokenForLaunch(page, api, launchHash!, "Graduated Task 6");
          return tokenAddress;
        },
        { timeout: 30_000 },
      )
      .toMatch(/^0x[0-9a-f]{40}$/i);
    await page.goto(`/token/${tokenAddress}`);
    await page.getByLabel("ETH input").fill("5");
    await page.getByRole("button", { name: "Review buy" }).click();
    await page.getByRole("button", { name: "Sign buy" }).click();
    await expect(page.getByRole("status").last()).toContainText(
      /indexing|indexed|safe|finalized/i,
      { timeout: 45_000 },
    );
    await expect
      .poll(
        async () => {
          const response = await page.request.get(`${api}/v1/tokens/${tokenAddress}`);
          if (!response.ok()) return "";
          return ((await response.json()) as { phase?: string }).phase ?? "";
        },
        { timeout: 30_000 },
      )
      .toBe("graduated");
    await page.reload();
    await expect(page.getByRole("heading", { name: "Router handoff" })).toBeVisible({
      timeout: 30_000,
    });
    await page.evaluate(() => {
      (window as unknown as { __task6ChainId: string }).__task6ChainId = "0x1";
    });
    await expect(page.getByText(/Wrong network/i)).toBeVisible();
    await page.getByRole("button", { name: "Switch network" }).click();
    await expect(page.getByText(/Wrong network/i)).toHaveCount(0);
    await page.getByLabel("ETH input").fill("0.001");
    await page.getByRole("button", { name: "Review buy" }).click();
    await expect(page.getByText(/0 ETH router fee/i)).toBeVisible();
    const evidenceDir = path.resolve(process.cwd(), "..", ".impeccable", "review");
    fs.mkdirSync(evidenceDir, { recursive: true });
    await page.screenshot({
      path: path.join(evidenceDir, `task6-graduated-confirm-${testInfo.project.name}.png`),
      fullPage: true,
    });
    await page.getByRole("button", { name: "Sign buy" }).click();
    await expect(page.getByRole("status").last()).toContainText(
      /indexing|indexed|safe|finalized/i,
      { timeout: 30_000 },
    );
    await page.getByRole("tab", { name: "Sell" }).click();
    await page.getByLabel(/GR6 input/).fill("1");
    await page.getByRole("button", { name: "Review sell" }).click();
    await page.getByRole("button", { name: "Sign sell" }).click();
    await expect(page.getByRole("status").last()).toContainText(/mined/i, { timeout: 30_000 });
    await page.getByRole("button", { name: "Resume sell" }).click();
    await page.screenshot({
      path: path.join(evidenceDir, `task6-graduated-approval-${testInfo.project.name}.png`),
      fullPage: true,
    });
    await page.getByRole("button", { name: "Sign sell" }).click();
    await expect(page.getByRole("status").last()).toContainText(
      /indexing|indexed|safe|finalized/i,
      { timeout: 30_000 },
    );
  });

  test("regresses to unavailable after the canonical launch disappears in an Anvil reorg", async ({
    page,
  }) => {
    await installWallet(page);
    const snapshotResponse = await page.request.post("/e2e/rpc", {
      data: { jsonrpc: "2.0", id: 1, method: "evm_snapshot", params: [] },
    });
    const snapshot = ((await snapshotResponse.json()) as { result: string }).result;
    await page.goto("/create");
    await page.getByRole("button", { name: "Connect wallet" }).last().click();
    await page.getByLabel("Token name").fill("Reorg Task 6");
    await page.getByLabel("Symbol").fill("RG6");
    await page.getByRole("button", { name: "Review launch" }).click();
    await page.getByRole("button", { name: "Sign launch" }).click();
    const status = page.getByRole("status").last();
    await expect(status).toContainText(/indexing|indexed|safe|finalized/i, { timeout: 30_000 });
    const hash = (await status.textContent())?.match(/0x[0-9a-f]{64}/i)?.[0];
    expect(hash).toBeTruthy();
    await expect
      .poll(
        async () =>
          (
            await page.request.get(`${process.env.TASK6_ANVIL_API_URL}/v1/transactions/${hash}`)
          ).status(),
        { timeout: 30_000 },
      )
      .toBe(200);
    const reverted = await page.request.post("/e2e/rpc", {
      data: { jsonrpc: "2.0", id: 2, method: "evm_revert", params: [snapshot] },
    });
    expect(((await reverted.json()) as { result: boolean }).result).toBe(true);
    await page.request.post("/e2e/rpc", {
      data: {
        jsonrpc: "2.0",
        id: 3,
        method: "eth_sendTransaction",
        params: [{ from: sender, to: sender, value: "0x1" }],
      },
    });
    await expect
      .poll(
        async () =>
          (
            await page.request.get(`${process.env.TASK6_ANVIL_API_URL}/v1/transactions/${hash}`)
          ).status(),
        { timeout: 30_000 },
      )
      .toBe(404);
    await expect(status).toContainText(/indexing/i, { timeout: 30_000 });
  });
});
