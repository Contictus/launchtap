import { expect, test } from "@playwright/test";

test("malformed token address has a stable not-found state", async ({ page }) => {
  await page.goto("/token/not-an-address");
  await expect(page.getByRole("heading", { name: "Token not found" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Return to Explore" })).toBeVisible();
});

test("valid token route fails closed when deployment is unavailable", async ({ page }) => {
  await page.goto("/token/0x0000000000000000000000000000000000000001");
  await expect(page.getByRole("heading", { name: "Token unavailable" })).toBeVisible();
  await expect(page.getByText("reviewed deployment is not configured")).toBeVisible();
  await expect(page.locator("body")).not.toContainText("Heatmap");
});

test("token route remains readable with reduced motion", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/token/not-an-address");
  await expect(page.getByRole("heading", { name: "Token not found" })).toBeVisible();
});
