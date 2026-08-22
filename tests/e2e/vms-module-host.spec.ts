import { expect, test } from '@playwright/test'

test('平台宿主从 VMS 子仓加载车辆管理页面', async ({ page }) => {
  test.setTimeout(120_000)
  const runtimeErrors: string[] = []

  page.on('pageerror', (error) => runtimeErrors.push(error.message))
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text())
  })

  await page.goto('/#/vms/vehicle-archive-manage', { waitUntil: 'domcontentloaded' })
  await expect(page.getByRole('heading', { name: '车辆档案管理' })).toBeVisible({
    timeout: 60_000
  })
  await expect(page.locator('.route-error')).toHaveCount(0)
  expect(runtimeErrors).toEqual([])
})
