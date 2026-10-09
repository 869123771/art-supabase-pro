import { expect, test } from '@playwright/test'
import { prepareIsolatedSession } from './support/isolated-session'

test.use({ storageState: { cookies: [], origins: [] }, actionTimeout: 30_000 })
test.setTimeout(240_000)
test('公共文件大小格式与上传文案一致', async ({ page }, info) => {
  await prepareIsolatedSession(page)
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error.message))
  await page.route('**/rest/v1/**', (route) => route.fulfill({ json: [] }))
  await page.goto('/tests/e2e/fixtures/file-size-reuse.html')
  await expect(page.getByText('0 B', { exact: true })).toBeVisible()
  await expect(page.getByText('大小未知', { exact: true })).toBeVisible()
  await expect(page.getByText('1.0 GB', { exact: true })).toBeVisible()
  await expect(page.getByText(/^单个文件不超过 20 MB/)).toBeVisible()
  await expect(page.getByText(/^单个文件不超过 1 GB/)).toBeVisible()
  await page.screenshot({ path: info.outputPath('file-size.png') })
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
  ).toBeLessThanOrEqual(1)
  expect(errors).toEqual([])
})
