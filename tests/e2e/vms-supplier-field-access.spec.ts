import { expect, test, type Page } from '@playwright/test'

async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const viewport = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }))
  expect(viewport.scrollWidth).toBeLessThanOrEqual(viewport.clientWidth + 1)
}

test('供应商敏感字段页面与编辑弹窗保持完整可用', async ({ page }, testInfo) => {
  test.setTimeout(120_000)
  const pageErrors: string[] = []
  page.on('pageerror', (error) => pageErrors.push(error.message))

  await page.goto('/#/vms/basic-info/supplier', { waitUntil: 'domcontentloaded' })
  await expect(page).not.toHaveURL(/#\/(?:auth\/)?login/)
  await expect(page.locator('.supplier-page')).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 60_000 })

  await expect(page.getByText('供应厂商', { exact: true }).first()).toBeVisible()
  for (const label of ['供应厂商名称', '联系人', '联系电话']) {
    await expect(page.getByText(label, { exact: true }).first()).toBeVisible()
  }

  const addButton = page.getByRole('button', { name: '新增', exact: true }).first()
  await expect(addButton).toBeVisible({ timeout: 30_000 })
  await addButton.click()

  const dialog = page.locator('.el-dialog').filter({ hasText: '新增供应厂商' })
  await expect(dialog).toBeVisible({ timeout: 30_000 })
  await expect(dialog.getByRole('textbox', { name: '供应厂商名称' })).toBeVisible()
  await expect(dialog.getByRole('textbox', { name: '联系人' })).toBeVisible()
  await expect(dialog.getByRole('textbox', { name: '联系电话' })).toBeVisible()
  await expect(dialog.getByRole('textbox', { name: '详细地址' })).toBeVisible()
  await expect(dialog.getByRole('textbox', { name: '备注' })).toBeVisible()

  const dialogOverflow = await dialog.evaluate((element) => ({
    clientWidth: element.clientWidth,
    scrollWidth: element.scrollWidth
  }))
  expect(dialogOverflow.scrollWidth).toBeLessThanOrEqual(dialogOverflow.clientWidth + 1)
  await expectNoHorizontalOverflow(page)

  await page.screenshot({
    path: testInfo.outputPath('supplier-field-access.png'),
    fullPage: true,
    animations: 'disabled'
  })
  expect(pageErrors).toEqual([])
})
