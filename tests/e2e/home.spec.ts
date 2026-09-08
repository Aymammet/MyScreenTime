import { expect, test } from "@playwright/test";

test("shows the project landing page", async ({ page }) => {
  await page.goto("/");

  await expect(
    page.getByRole("heading", { name: "MyScreenTime" }),
  ).toBeVisible();
  await expect(page.getByText("Project foundation ready")).toBeVisible();
});
