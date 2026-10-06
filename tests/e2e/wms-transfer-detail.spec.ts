import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })
test('直接调拨详情完整显示长物料名称、备注并约束序列号宽度', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error.message))
  await page.goto('/tests/e2e/fixtures/wms-transfer-detail.html')
  await page.getByRole('button', { name: '查看测试调拨详情' }).click()
  const drawer = page.getByRole('dialog', { name: '直接调拨单', exact: true })
  await expect(drawer.getByText('物料编码', { exact: true })).toBeVisible()
  await expect(drawer.getByText('TEST-MATERIAL-001', { exact: true })).toBeVisible()
  await expect(drawer.getByText('测试长名称物料'.repeat(12), { exact: true })).toBeVisible()
  const overflow = await drawer.evaluate((element) =>
    Array.from(element.querySelectorAll('.el-descriptions, li')).map((region) => ({
      width: region.clientWidth,
      overflow: region.scrollWidth - region.clientWidth
    }))
  )
  expect(overflow.every((region) => region.width > 0 && region.overflow <= 1)).toBe(true)
  await drawer.getByRole('button', { name: '关闭此对话框', exact: true }).click()
  await expect(drawer).not.toBeVisible()
  expect(errors).toEqual([])
})
