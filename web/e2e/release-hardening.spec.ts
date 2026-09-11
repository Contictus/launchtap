import path from "node:path";

import { expect, test } from "@playwright/test";

const coreRoutes = ["/", "/graduated", "/create", "/analytics", "/docs", "/profile"];

test("production responses expose hardened headers and safe caching", async ({ page }) => {
  const response = await page.goto("/");
  expect(response?.status()).toBe(200);
  const headers = response?.headers() ?? {};
  expect(headers["content-security-policy"]).toContain("default-src 'self'");
  expect(headers["content-security-policy"]).not.toMatch(/connect-src[^;]*\shttps:(?:\s|;)/);
  expect(headers["x-content-type-options"]).toBe("nosniff");
  expect(headers["x-frame-options"]).toBe("DENY");
  expect(headers["referrer-policy"]).toBe("strict-origin-when-cross-origin");
  expect(headers["cache-control"]).toContain("no-store");
});

test("missing routes use the first-class not-found boundary", async ({ page }) => {
  const response = await page.goto("/route-that-does-not-exist");
  expect(response?.status()).toBe(404);
  await expect(
    page.getByRole("heading", { name: "That launch route does not exist." }),
  ).toBeVisible();
  await expect(page.getByRole("link", { name: "Return to Explore" })).toBeVisible();
});

test("core routes stay within the browser navigation budget", async ({ page }) => {
  for (const route of coreRoutes) {
    const response = await page.goto(route, { waitUntil: "domcontentloaded" });
    expect(response?.status(), route).toBe(200);
    const duration = await page.evaluate(
      () => performance.getEntriesByType("navigation")[0]?.duration ?? 0,
    );
    expect(duration, `${route} navigation`).toBeLessThan(5000);
  }
});

test("reduced motion preserves route content without authored transition motion", async ({
  page,
}, testInfo) => {
  if (testInfo.project.name === "reduced-motion")
    await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Explore the launch route." })).toBeVisible();
  await page.screenshot({
    path: path.resolve(
      process.cwd(),
      "..",
      ".impeccable",
      "review",
      `task8-release-${testInfo.project.name}.png`,
    ),
    fullPage: true,
  });
  if (testInfo.project.name === "reduced-motion") {
    await expect(page.locator("html")).toHaveCSS("scroll-behavior", "auto");
    await expect(
      page.evaluate(() => window.matchMedia("(prefers-reduced-motion: reduce)").matches),
    ).resolves.toBe(true);
  }
});
