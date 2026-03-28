import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  timeout: 30_000,
  retries: 1,
  use: {
    // UI tests hit the Vite dev server which proxies API calls to corvia-server.
    // API-only tests use the request context with baseURL below.
    baseURL: "http://localhost:8021",
    screenshot: "only-on-failure",
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: { browserName: "chromium" },
    },
  ],
  webServer: {
    command: "npx vite --port 8021 --host",
    port: 8021,
    reuseExistingServer: true,
    timeout: 15_000,
  },
});
