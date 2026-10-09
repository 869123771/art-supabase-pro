import { expect, test } from '@playwright/test'
import { prepareIsolatedSession } from './support/isolated-session'

test.use({ storageState: { cookies: [], origins: [] }, actionTimeout: 15_000 })
test.setTimeout(90_000)
for (const theme of ['light', 'dark'])
  for (const box of ['border-mode', 'shadow-mode']) {
    test(`上传来源标签 ${theme} ${box}`, async ({ page }, info) => {
      await prepareIsolatedSession(page)
      const errors: string[] = []
      page.on('pageerror', (error) => errors.push(error.message))
      await page.route('**/rest/v1/**', (route) => route.fulfill({ json: [] }))
      await page.goto(`/tests/e2e/fixtures/upload-source-label.html?theme=${theme}&box=${box}`)
      const normal = page.locator('[data-mode="normal"]')
      const toggle = normal.locator('.art-upload-file__source-toggle')
      await expect(toggle).toContainText('资源库')
      await toggle.click()
      await expect(toggle.getByRole('checkbox')).toBeChecked()
      await expect(
        normal.getByRole('button', { name: '从资源管理器选择', exact: true })
      ).toBeVisible()
      expect(
        await normal
          .locator('.art-upload-file')
          .evaluate((element) => element.scrollWidth <= element.clientWidth + 1)
      ).toBe(true)
      await toggle.click()
      await expect(toggle.getByRole('checkbox')).not.toBeChecked()
      await expect(normal.getByText('选择附件', { exact: true })).toBeVisible()
      await expect(page.locator('[data-mode="disabled"]').getByRole('checkbox')).toHaveCount(0)
      await expect(
        page
          .locator('[data-mode="disabled"]')
          .getByRole('button', { name: '选择附件', exact: true })
      ).toBeDisabled()
      await expect(page.locator('[data-mode="readonly"]').getByRole('checkbox')).toHaveCount(0)
      expect(
        await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)
      ).toBe(true)
      expect(errors).toEqual([])
      await page.screenshot({ path: info.outputPath('sources.png'), fullPage: true })
    })
  }
