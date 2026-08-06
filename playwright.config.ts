import { defineConfig } from '@playwright/test'

const baseURL = process.env.E2E_BASE_URL || 'http://127.0.0.1:41737'
const browserChannel = process.env.E2E_BROWSER_CHANNEL as 'chrome' | 'msedge' | undefined

export default defineConfig({
  testDir: './tests/e2e',
  outputDir: '.artifacts/playwright',
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: process.env.CI
    ? [['line'], ['html', { outputFolder: 'playwright-report', open: 'never' }]]
    : [['list'], ['html', { outputFolder: 'playwright-report', open: 'never' }]],
  snapshotPathTemplate: '{testDir}/__screenshots__/{testFilePath}/{projectName}/{arg}{ext}',
  expect: {
    timeout: 10_000,
    toHaveScreenshot: {
      animations: 'disabled',
      caret: 'hide',
      maxDiffPixelRatio: 0.01,
      stylePath: './tests/e2e/visual-stability.css'
    }
  },
  use: {
    baseURL,
    channel: browserChannel,
    locale: 'zh-CN',
    timezoneId: 'Asia/Shanghai',
    colorScheme: 'light',
    reducedMotion: 'reduce',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure'
  },
  projects: [
    {
      name: 'setup',
      testMatch: /auth\.setup\.ts/
    },
    {
      name: 'desktop-1440',
      dependencies: ['setup'],
      testIgnore: /auth\.setup\.ts/,
      use: {
        viewport: { width: 1440, height: 900 },
        storageState: 'playwright/.auth/user.json'
      }
    },
    {
      name: 'desktop-1280',
      dependencies: ['setup'],
      testIgnore: /auth\.setup\.ts/,
      use: {
        viewport: { width: 1280, height: 800 },
        storageState: 'playwright/.auth/user.json'
      }
    },
    {
      name: 'mobile-390',
      dependencies: ['setup'],
      testIgnore: /auth\.setup\.ts/,
      use: {
        viewport: { width: 390, height: 844 },
        isMobile: true,
        hasTouch: true,
        storageState: 'playwright/.auth/user.json'
      }
    }
  ],
  webServer: process.env.E2E_BASE_URL
    ? undefined
    : {
        command: 'node scripts/serve-e2e.mjs',
        url: baseURL,
        reuseExistingServer: !process.env.CI,
        timeout: 120_000
      }
})
