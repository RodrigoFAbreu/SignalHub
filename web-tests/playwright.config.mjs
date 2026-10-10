import { defineConfig, devices } from "@playwright/test";

// The tests drive a SignalHub that is already running (SIGNALHUB_URL, default
// http://localhost:8080) and set it up through the operator's token (ADMIN_TOKEN), which only the
// test setup uses. Chromium comes from Playwright, or from PLAYWRIGHT_CHROMIUM_EXECUTABLE (for
// example /opt/pw-browsers/chromium-*/chrome-linux/chrome).
const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined;

export default defineConfig({
  testDir: "tests",
  timeout: 45_000,
  expect: { timeout: 8_000 },
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  outputDir: ".results",
  use: {
    baseURL: process.env.SIGNALHUB_URL ?? "http://localhost:8080",
    ...devices["Desktop Chrome"],
    viewport: { width: 1280, height: 800 },
    launchOptions: { executablePath },
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium" }],
});
