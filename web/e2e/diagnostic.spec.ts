import { expect, test } from "@playwright/test";

test("application shell reports fail-closed configuration", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Explore the launch route." })).toBeVisible();
  await expect(page.getByText("fail-closed")).toBeVisible();
  await expect(page.getByText("Not configured").first()).toBeVisible();
  await expect(
    page.getByRole("navigation", { name: /^(Desktop|Mobile) primary navigation$/ }),
  ).toBeVisible();
});

test("mobile shell keeps primary routes keyboard reachable", async ({ page }) => {
  await page.setViewportSize({ width: 360, height: 800 });
  await page.goto("/");
  await expect(page.getByRole("navigation", { name: "Mobile primary navigation" })).toBeVisible();
  await page.getByRole("button", { name: "Open navigation" }).focus();
  await expect(page.getByRole("button", { name: "Open navigation" })).toBeFocused();
  await page.getByRole("button", { name: "Open navigation" }).click();
  const drawer = page.getByRole("dialog", { name: "Navigate" });
  await expect(drawer).toBeVisible();
  for (const label of ["Explore", "Graduated", "Create", "Analytics", "Docs", "Profile"]) {
    await expect(drawer.getByRole("link", { name: label })).toBeVisible();
  }
});

test("graduated route canonicalizes a conflicting phase and stays scoped", async ({ page }) => {
  await page.goto("/graduated?phase=curve&sort=market_cap");
  await expect(page.getByRole("heading", { name: "Graduated routes", exact: true })).toBeVisible();
  await expect(page.getByLabel("Phase")).toHaveCount(0);
  await expect(page).toHaveURL(/\/graduated\?sort=market_cap$/);
});

test("discovery filters restore through browser history", async ({ page }) => {
  await page.goto("/");
  await page.getByLabel("Sort").selectOption("volume_24h");
  await expect(page).toHaveURL(/\/\?sort=volume_24h$/);
  await page.goBack();
  await expect(page).toHaveURL(/127\.0\.0\.1:3000\/$/);
  await expect(page.getByLabel("Sort")).toHaveValue("newest");
  await page.goForward();
  await expect(page).toHaveURL(/\/\?sort=volume_24h$/);
  await expect(page.getByLabel("Sort")).toHaveValue("volume_24h");
});
