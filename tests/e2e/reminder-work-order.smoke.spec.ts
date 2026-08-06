import { expect, test } from '@playwright/test'

test('车辆到期提醒可建立并查看处置单', async ({ page }) => {
  test.setTimeout(90_000)
  const pageErrors: string[] = []
  page.on('pageerror', (error) => pageErrors.push(error.message))

  await page.goto('/#/vehicle-manage-system/reminder-manage/insurance-expiry', {
    waitUntil: 'domcontentloaded'
  })
  await expect(page).not.toHaveURL(/#\/auth\/login/)
  await expect(page.locator('.art-table-query').first()).toBeVisible({ timeout: 30_000 })
  await page
    .locator('.el-loading-mask')
    .waitFor({ state: 'hidden', timeout: 20_000 })
    .catch(() => {})

  const row = page
    .locator('.el-table__body-wrapper tbody tr')
    .filter({ hasText: '沪B30006' })
    .first()
  await expect(row).toBeVisible({ timeout: 30_000 })
  await expect(row.getByRole('button', { name: '查看' })).toBeEnabled()
  await row.getByRole('button', { name: '查看' }).click()

  await expect(page.getByText('保险到期处置单', { exact: true })).toBeVisible({ timeout: 30_000 })
  await expect(page.getByText('处置进度', { exact: true })).toBeVisible({ timeout: 30_000 })
  await expect(page.getByText('沪B30006 · 保险到期', { exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: '提交流转' })).toBeVisible()

  const pageOverflow = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }))
  expect(pageOverflow.scrollWidth).toBeLessThanOrEqual(pageOverflow.clientWidth + 1)

  const drawer = page.locator('.el-drawer').filter({ hasText: '保险到期处置单' })
  await expect(drawer).toBeVisible()
  await page.screenshot({ path: '.artifacts/reminder-work-order-desktop.png', fullPage: true })

  await page.setViewportSize({ width: 390, height: 844 })
  await expect(drawer).toBeVisible()
  const drawerOverflow = await drawer.evaluate((element) => ({
    clientWidth: element.clientWidth,
    scrollWidth: element.scrollWidth
  }))
  expect(drawerOverflow.scrollWidth).toBeLessThanOrEqual(drawerOverflow.clientWidth + 1)
  const drawerBody = drawer.locator('.el-drawer__body')
  await drawerBody.evaluate((element) => element.scrollTo({ top: element.scrollHeight }))
  await expect(page.getByText('下一状态', { exact: true })).toBeVisible()
  await page.screenshot({ path: '.artifacts/reminder-work-order-mobile.png', fullPage: true })

  expect(pageErrors).toEqual([])
})
