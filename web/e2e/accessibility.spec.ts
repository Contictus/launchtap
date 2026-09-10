import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const routes = ["/", "/graduated", "/create", "/analytics", "/docs", "/profile"];

test("shell routes have no serious or critical accessibility violations", async ({ page }) => {
  for (const route of routes) {
    const response = await page.goto(route);
    expect(response?.status(), `${route} should load successfully`).toBe(200);
    const results = await new AxeBuilder({ page }).analyze();
    const seriousOrCritical = results.violations.filter((violation) =>
      ["serious", "critical"].includes(violation.impact ?? ""),
    );
    expect(seriousOrCritical, `${route} accessibility violations`).toEqual([]);
  }
});

test("analytics tabs expose their panels and keyboard order", async ({ page }) => {
  await page.goto("/analytics");
  const tabs = page.getByRole("tab");
  await expect(tabs).toHaveCount(2);
  await expect(tabs.nth(0)).toHaveAttribute("aria-controls", /panel/);
  await expect(page.getByRole("tabpanel", { includeHidden: true })).toHaveCount(2);
  await expect(tabs.nth(0)).toHaveAttribute("tabindex", "0");
  await tabs.nth(0).press("End");
  await expect(tabs.nth(1)).toBeFocused();
  await expect(tabs.nth(1)).toHaveAttribute("tabindex", "0");
});
