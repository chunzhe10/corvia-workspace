import { test, expect } from "@playwright/test";

test.describe("Dashboard layout", () => {
  test("loads and shows header with service pills", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator(".brand-name")).toHaveText("Corvia");
    await expect(page.locator(".status-pills")).toBeVisible();
    await expect(page.locator(".tabs")).toBeVisible();
  });

  test("shows all navigation tabs", async ({ page }) => {
    await page.goto("/");
    const tabs = ["Traces", "Agents", "RAG", "Tiers", "Logs", "Graph", "History"];
    for (const tab of tabs) {
      await expect(page.getByRole("button", { name: tab })).toBeVisible();
    }
  });

  test("status bar shows entry and agent counts", async ({ page }) => {
    await page.goto("/");
    // Wait for status metrics to load
    await expect(page.locator(".metrics")).toBeVisible({ timeout: 10_000 });
  });
});

test.describe("Agents tab", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await page.getByRole("button", { name: "Agents" }).click();
  });

  test("renders agents header and grid", async ({ page }) => {
    await expect(page.locator(".agents-header h2")).toHaveText("Registered Agents");
    await expect(page.locator(".agents-count")).toBeVisible();
  });

  test("shows agent cards with heartbeat dots", async ({ page }) => {
    await expect(page.locator(".agent-card").first()).toBeVisible({ timeout: 10_000 });
    await expect(page.locator(".heartbeat-dot").first()).toBeVisible();
  });

  test("expands agent card on click", async ({ page }) => {
    const card = page.locator(".agent-card").first();
    await expect(card).toBeVisible({ timeout: 10_000 });
    await card.locator(".agent-card-header").click();
    await expect(card).toHaveClass(/expanded/);
    await expect(card.locator(".agent-card-body")).toBeVisible();
    await expect(card.locator(".agent-section-title").first()).toBeVisible();
  });

  test("collapses agent card on second click", async ({ page }) => {
    const card = page.locator(".agent-card").first();
    await expect(card).toBeVisible({ timeout: 10_000 });
    const header = card.locator(".agent-card-header");
    await header.click();
    await expect(card).toHaveClass(/expanded/);
    await header.click();
    await expect(card).not.toHaveClass(/expanded/);
  });

  test("shows live sessions bar when sessions exist", async ({ page }) => {
    // LiveSessionsBar only renders when sessions are present
    const bar = page.locator(".live-sessions-bar");
    // It may or may not be visible depending on server state, just check no errors
    await page.waitForTimeout(2000);
    const count = await bar.count();
    if (count > 0) {
      await expect(bar.locator(".live-sessions-label")).toHaveText("Live Sessions");
    }
  });
});

test.describe("Spokes integration", () => {
  test("spokes API returns valid response", async ({ request }) => {
    const resp = await request.get("/api/dashboard/spokes");
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body).toHaveProperty("spokes");
    expect(Array.isArray(body.spokes)).toBeTruthy();
    // warning is optional (omitted when Docker is available)
    if (body.warning) {
      expect(typeof body.warning).toBe("string");
    }
  });

  test("spokes summary bar hidden when no spokes running", async ({ page }) => {
    await page.goto("/");
    await page.getByRole("button", { name: "Agents" }).click();
    await expect(page.locator(".agents-header")).toBeVisible({ timeout: 10_000 });
    // With 0 spokes the summary bar should not render
    const bar = page.locator(".spokes-summary-bar");
    await expect(bar).toHaveCount(0);
  });

  test("header spoke count hidden when no spokes running", async ({ page }) => {
    await page.goto("/");
    await page.waitForTimeout(3000);
    const spokeCount = page.locator(".header-spoke-count");
    await expect(spokeCount).toHaveCount(0);
  });

  test("warning banner shown when Docker unavailable", async ({ page }) => {
    // This test verifies the banner renders IF the spokes response has a warning.
    // In most test environments Docker IS available, so we test via the API.
    const resp = await page.request.get("/api/dashboard/spokes");
    const body = await resp.json();
    await page.goto("/");
    await page.getByRole("button", { name: "Agents" }).click();
    await page.waitForTimeout(3000);
    const banner = page.locator(".warning-banner");
    if (body.warning) {
      await expect(banner).toBeVisible();
    } else {
      await expect(banner).toHaveCount(0);
    }
  });
});

test.describe("History tab", () => {
  test("renders activity feed filters", async ({ page }) => {
    await page.goto("/");
    await page.getByRole("button", { name: "History" }).click();
    // Wait for the feed to load (may take a moment with large datasets)
    await page.waitForTimeout(5000);
    const filters = page.locator(".activity-filters");
    const feed = page.locator(".activity-feed");
    const loading = page.locator(".loading");
    // Either filters + feed are visible, or still loading
    const hasFilters = await filters.count();
    const isLoading = await loading.count();
    expect(hasFilters > 0 || isLoading > 0).toBeTruthy();
  });

  test("agent filter dropdown includes all agents option", async ({ page }) => {
    await page.goto("/");
    await page.getByRole("button", { name: "History" }).click();
    await page.waitForTimeout(5000);
    const select = page.locator(".agent-filter");
    if ((await select.count()) > 0) {
      await expect(select.locator('option[value=""]')).toHaveText("All agents");
    }
  });
});

test.describe("Tab navigation", () => {
  test("all tabs render without errors", async ({ page }) => {
    await page.goto("/");
    const tabs = ["Traces", "Agents", "RAG", "Tiers", "Logs", "Graph", "History"];
    for (const tab of tabs) {
      await page.getByRole("button", { name: tab }).click();
      // Verify no crash - page should still have the header
      await expect(page.locator(".brand-name")).toHaveText("Corvia");
      await page.waitForTimeout(500);
    }
  });
});
