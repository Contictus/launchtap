import { defineConfig, devices } from "@playwright/test";

const fixtureFactory = process.env.TASK6_ANVIL_FACTORY ?? "";
const fixtureRpc = process.env.TASK6_ANVIL_RPC_URL ?? "";

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  workers: 1,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 2 : 0,
  reporter: "line",
  use: { baseURL: "http://127.0.0.1:3000", trace: "on-first-retry" },
  webServer: {
    // Build with the E2E-only fixture flag, then exercise the production server and CSP.
    command: "npm run build && npm run start",
    env: {
      NEXT_PUBLIC_E2E_FIXTURE: "1",
      TASK6_ANVIL_FACTORY: fixtureFactory,
      TASK6_ANVIL_RPC_URL: fixtureRpc,
      NEXT_PUBLIC_TASK6_ANVIL_FACTORY: fixtureFactory,
      NEXT_PUBLIC_TASK6_ANVIL_RPC_URL: fixtureRpc,
    },
    url: "http://127.0.0.1:3000",
    reuseExistingServer: false,
  },
  projects: [
    {
      name: "desktop",
      use: {
        ...devices["Desktop Chrome"],
        launchOptions: {
          executablePath: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
        },
      },
    },
    {
      name: "mobile",
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 360, height: 800 },
        launchOptions: {
          executablePath: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
        },
      },
    },
  ],
});
