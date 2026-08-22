import { expect, test, type Page } from '@playwright/test'

async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const viewport = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }))
  expect(viewport.scrollWidth).toBeLessThanOrEqual(viewport.clientWidth + 1)
}

function collectPageErrors(page: Page): string[] {
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error.message))
  return errors
}

test('订单录入可添加货品且保持非提交状态', async ({ page }) => {
  test.setTimeout(180_000)
  const pageErrors = collectPageErrors(page)

  await page.goto('/#/tms/order-open', { waitUntil: 'domcontentloaded' })
  await expect(page).not.toHaveURL(/#\/auth\/login/)
  await expect(page.locator('.order-open')).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 60_000 })

  const cargoSection = page.locator('.order-open__section').filter({ hasText: '货品信息' })
  const cargoRows = cargoSection.locator('.el-table__body-wrapper tbody tr')
  await expect(cargoRows).toHaveCount(1, { timeout: 30_000 })
  await cargoSection.getByRole('button', { name: '批量选合同明细', exact: true }).click()
  const contractDetailDialog = page.locator('.el-dialog').filter({ hasText: '批量选择合同明细' })
  await expect(contractDetailDialog).toBeVisible({ timeout: 30_000 })
  await expect(contractDetailDialog.getByText('合同编号', { exact: true })).toBeVisible()
  await expect(contractDetailDialog.getByText('货物名称', { exact: true })).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(contractDetailDialog).toBeHidden()
  await cargoSection.getByRole('button', { name: '添加', exact: true }).click()
  await expect(cargoRows).toHaveCount(2)

  await expectNoHorizontalOverflow(page)
  expect(pageErrors).toEqual([])
})

test('发票登记对话框可打开并呈现完整录入状态', async ({ page }) => {
  test.setTimeout(180_000)
  const pageErrors = collectPageErrors(page)

  await page.goto('/#/fms/invoice-management', {
    waitUntil: 'domcontentloaded'
  })
  await expect(page.locator('.art-table-query')).toBeVisible({ timeout: 120_000 })
  await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 120_000 })
  await page.getByRole('button', { name: '登记发票', exact: true }).click()

  const dialog = page.locator('.el-dialog').filter({ hasText: '登记发票' })
  await expect(dialog).toBeVisible({ timeout: 30_000 })
  await expect(dialog.getByRole('textbox', { name: '登记单号' })).toBeVisible()
  const dialogOverflow = await dialog.evaluate((element) => ({
    clientWidth: element.clientWidth,
    scrollWidth: element.scrollWidth
  }))
  expect(dialogOverflow.scrollWidth).toBeLessThanOrEqual(dialogOverflow.clientWidth + 1)

  await expectNoHorizontalOverflow(page)
  expect(pageErrors).toEqual([])
})
