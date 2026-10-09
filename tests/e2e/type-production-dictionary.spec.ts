import { expect, test } from '@playwright/test'
import { prepareIsolatedSession } from './support/isolated-session'

test.use({ storageState: { cookies: [], origins: [] }, actionTimeout: 30_000 })
test.setTimeout(180_000)
test('生产单据仓库范围与扩展字段复用公共字典', async ({ page }, info) => {
  await prepareIsolatedSession(page)
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error.message))
  await page.route('**/rest/v1/**', (route) => {
    const url = new URL(route.request().url())
    return route.fulfill({
      json: url.pathname.endsWith('/sys_dictionary')
        ? [
            { label: '', name: '公共选项名称', value: 'number', status: '1' },
            { label: '停用选项', value: 'inactive', status: '0' }
          ]
        : []
    })
  })
  await page.goto('/tests/e2e/fixtures/type-dictionary-reuse.html?mode=document-production')
  await page.getByRole('button', { name: '打开表单' }).click()
  const dialog = page.getByRole('dialog', { name: '新增单据类型' })
  const warehouse = dialog
    .locator('.el-form-item')
    .filter({ has: page.getByText('允许领料的仓库类型', { exact: true }) })
    .locator('.el-select')
  await warehouse.click()
  await expect(page.getByRole('option', { name: '公共选项名称', exact: true })).toBeVisible()
  await expect(page.getByRole('option', { name: '停用选项', exact: true })).toHaveCount(0)
  await page.getByRole('option', { name: '公共选项名称', exact: true }).click()
  await page.keyboard.press('Escape')
  await dialog.screenshot({ path: info.outputPath('production-warehouse.png') })
  await dialog
    .locator('.el-form-item')
    .filter({ has: page.getByText('需要排包', { exact: true }) })
    .getByRole('switch')
    .locator('..')
    .click()
  await dialog.getByRole('button', { name: '新增字段', exact: true }).click()
  await dialog
    .getByRole('combobox', { name: '第 1 个字段类型', exact: true })
    .locator('xpath=ancestor::div[contains(@class, "el-select__wrapper")]')
    .click()
  await expect(page.getByRole('option', { name: '公共选项名称', exact: true })).toBeVisible()
  await expect(page.getByRole('option', { name: '停用选项', exact: true })).toHaveCount(0)
  await page.getByRole('option', { name: '公共选项名称', exact: true }).click()
  await dialog.screenshot({ path: info.outputPath('production-extension.png') })
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
  ).toBeLessThanOrEqual(1)
  expect(errors).toEqual([])
})
