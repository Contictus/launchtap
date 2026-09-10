import { defineConfig, devices } from "@playwright/test";

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
    command: 'cmd /c "set NEXT_PUBLIC_E2E_FIXTURE=1&& npm run build && npm run start"',
    url: "http://127.0.0.1:3000",
    reuseExistingServer: !process.env.CI,
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
