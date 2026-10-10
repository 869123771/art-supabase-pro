import { expect, test } from '@playwright/test'
import { prepareIsolatedSession } from './support/isolated-session'
test('车辆摘要复用详情样式且窄屏无溢出', async ({ page }, info) => {
  await prepareIsolatedSession(page)
  await page.goto('/tests/e2e/fixtures/vehicle-summary-reuse.html')
  await expect(page.locator('.vehicle-query-summary')).toContainText('测试车辆')
  await expect(page.locator('.vehicle-query-summary')).toContainText('12,345.67')
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
  ).toBeLessThanOrEqual(1)
  const label = page.locator('.el-descriptions__label').first()
  expect(await label.evaluate((el) => getComputedStyle(el).width)).toBe('128px')
  await page.screenshot({ path: info.outputPath('summary.png'), fullPage: true })
})

test('车辆档案页签和证件布局复用公共详情', async ({ page }, info) => {
  await prepareIsolatedSession(page)
  await page.goto('/tests/e2e/fixtures/vehicle-summary-reuse.html?archive')
  await expect(page.locator('.vehicle-query-archive-panel')).toContainText('测试车辆')
  await expect(page.locator('.vehicle-query-archive-panel__image-item')).toHaveCount(4)
  for (const name of ['车身参数', '发动机参数', '其他信息', '基础信息']) {
    await page.getByRole('tab', { name, exact: true }).click()
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
    ).toBeLessThanOrEqual(1)
  }
  await page.screenshot({ path: info.outputPath('archive.png'), fullPage: true })
})
