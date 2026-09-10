import { expect, test } from "@playwright/test";

test("diagnostic shell reports fail-closed configuration", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Web boundary is ready." })).toBeVisible();
  await expect(page.getByText("fail-closed")).toBeVisible();
  await expect(page.getByText("not configured").first()).toBeVisible();
});
