import { expect, test, type Page } from '@playwright/test'
import ExcelJS from 'exceljs'
import { prepareIsolatedSession } from './support/isolated-session'

test.use({ storageState: { cookies: [], origins: [] }, actionTimeout: 30_000 })
test.setTimeout(180_000)
async function mockMovement(page: Page, gate: Promise<void> = Promise.resolve()) {
  await page.route('**/rest/v1/**', async (route) => {
    const url = new URL(route.request().url())
    let json: unknown = []
    if (url.pathname.endsWith('/sys_dictionary')) {
      await gate
      json = url.search.includes('commonBoolean')
        ? [
            { label: '公共肯定', value: 'true', status: '1' },
            { label: '公共否定', value: 'false', status: '1' }
          ]
        : url.search.includes('mdmInventoryMovementType')
          ? [{ label: '', name: '采购入库名称', value: 'purchase_in', status: '0' }]
          : [
              { label: '', name: '公共入库名称', value: 'inbound', status: '1' },
              { label: '历史出库名称', value: 'outbound', status: '0' }
            ]
    } else if (url.pathname.endsWith('/mdm_stock_movement_type')) {
      json = ['inbound', 'outbound', 'transfer'].map((direction, index) => ({
        id: `movement-${index}`,
        tenant_id: 'test-tenant',
        movement_code: `MOVE-${index}`,
        movement_name: `公共字典测试移动-${index}`,
        direction,
        reversal: index === 0,
        other_io: index !== 0,
        status: 'enabled',
        reverse_type_id: null
      }))
    }
    await route.fulfill({
      json,
      headers: {
        'content-range': url.pathname.endsWith('/mdm_stock_movement_type') ? '0-2/3' : '*/0',
        'access-control-expose-headers': 'content-range'
      }
    })
  })
}

for (const mode of ['type', 'inventory']) {
  test(`${mode}弹窗使用公共字典并正确显示延迟返回的名称`, async ({ page }, info) => {
    await prepareIsolatedSession(page)
    const errors: string[] = []
    page.on('pageerror', (error) => errors.push(error.message))
    let release: () => void = () => {}
    await mockMovement(
      page,
      new Promise<void>((resolve) => {
        release = resolve
      })
    )
    await page.goto(`/tests/e2e/fixtures/movement-dictionary-reuse.html?mode=${mode}`)
    await page.getByRole('button', { name: '打开表单' }).click()
    const dialog = page.getByRole('dialog')
    await expect(dialog).toBeVisible()
    release()
    if (mode === 'type') {
      const field = dialog
        .locator('.el-form-item')
        .filter({ has: page.getByText('出入库类型', { exact: true }) })
      await expect(field.getByRole('radio', { name: '公共入库名称', exact: true })).toHaveCount(1)
      await expect(field.getByRole('radio', { name: '历史出库名称', exact: true })).toHaveCount(0)
      await field.getByRole('radio', { name: '公共入库名称', exact: true }).locator('..').click()
    } else {
      await expect(dialog).toHaveAccessibleName('采购入库名称 · 测试仓库')
      const field = dialog
        .locator('.el-form-item')
        .filter({ has: page.getByText('业务类型', { exact: true }) })
      await expect(field).toContainText('采购入库名称')
      await expect(field.locator('.el-select')).toHaveCount(0)
      await expect(dialog.locator('.art-entity-summary__content strong')).toContainText(
        '采购入库名称'
      )
    }
    await dialog.screenshot({ path: info.outputPath('movement-form.png') })
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
    ).toBeLessThanOrEqual(1)
    expect(errors).toEqual([])
  })
}

test('移动类型列表、搜索与导出统一字典显示并保留历史值', async ({ page }, info) => {
  await prepareIsolatedSession(page)
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error.message))
  await mockMovement(page)
  await page.goto('/tests/e2e/fixtures/movement-dictionary-reuse.html?mode=list')
  const table = page.locator('.el-table')
  await expect(table.getByText('公共入库名称', { exact: true })).toHaveCount(1)
  await expect(table.getByText('历史出库名称', { exact: true })).toHaveCount(1)
  await expect(table.getByText('transfer', { exact: true })).toHaveCount(1)
  const select = page
    .locator('.el-form-item')
    .filter({ has: page.getByText('出入标志', { exact: true }) })
    .locator('.el-select')
  await select.click()
  await expect(page.getByRole('option', { name: '历史出库名称', exact: true })).toHaveCount(0)
  await page.getByRole('option', { name: '公共入库名称', exact: true }).click()
  const pending = page.waitForEvent('download')
  await page.getByRole('button', { name: '导出', exact: true }).click()
  const path = await (await pending).path()
  if (!path) throw new Error('移动类型导出未生成文件')
  const workbook = new ExcelJS.Workbook()
  await workbook.xlsx.readFile(path)
  const sheet = workbook.worksheets[0]
  for (const [index, label] of ['公共入库名称', '历史出库名称', 'transfer'].entries()) {
    expect(sheet.getRow(index + 2).getCell(3).value).toBe(label)
    expect(sheet.getRow(index + 2).getCell(5).value).toBe(index === 0 ? '公共肯定' : '公共否定')
    expect(sheet.getRow(index + 2).getCell(6).value).toBe(index === 0 ? '公共否定' : '公共肯定')
  }
  const header = page.locator('.business-workspace-header')
  await page.getByRole('switch', { name: '进入专注模式', exact: true }).locator('..').click()
  await expect(header).toBeHidden()
  await page.getByRole('button', { name: '退出专注模式', exact: true }).click()
  await expect(header).toBeVisible()
  await page.getByRole('switch', { name: '进入专注模式', exact: true }).locator('..').click()
  await page.keyboard.press('Escape')
  await expect(header).toBeVisible()
  await page.screenshot({ path: info.outputPath('movement-list.png'), fullPage: true })
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
  ).toBeLessThanOrEqual(1)
  expect(errors).toEqual([])
})

test('库存业务字典失败后重新打开能够恢复名称', async ({ page }, info) => {
  await prepareIsolatedSession(page)
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error.message))
  await mockMovement(page)
  let unavailable = true
  await page.route('**/rest/v1/sys_dictionary?*', (route) =>
    route.fulfill({
      status: unavailable ? 503 : 200,
      json: unavailable
        ? { message: '测试字典暂不可用' }
        : [{ label: '', name: '采购入库名称', value: 'purchase_in', status: '0' }]
    })
  )
  await page.goto('/tests/e2e/fixtures/movement-dictionary-reuse.html?mode=inventory')
  await page.getByRole('button', { name: '打开表单' }).click()
  const dialog = page.getByRole('dialog')
  await expect(
    page.getByText('库存基础数据加载失败，请关闭弹窗后重试', { exact: true })
  ).toBeVisible()
  await expect(
    dialog.locator('.el-form-item').filter({ has: page.getByText('业务类型', { exact: true }) })
  ).toContainText('purchase_in')
  await dialog.screenshot({ path: info.outputPath('movement-dictionary-error.png') })
  await dialog.getByRole('button', { name: '取消', exact: true }).click()
  await expect(dialog).toBeHidden()
  unavailable = false
  await page.getByRole('button', { name: '打开表单' }).click()
  await expect(dialog).toHaveAccessibleName('采购入库名称 · 测试仓库')
  await expect(dialog.locator('.art-entity-summary__content strong')).toContainText('采购入库名称')
  await dialog.screenshot({ path: info.outputPath('movement-dictionary-retry.png') })
  expect(errors).toEqual([])
})

test('关闭并重开后旧请求不能覆盖新库存弹窗', async ({ page }) => {
  await prepareIsolatedSession(page)
  await mockMovement(page)
  let release: () => void = () => {}
  const gate = new Promise<void>((resolve) => {
    release = resolve
  })
  let requestCount = 0
  await page.route('**/rest/v1/mdm_warehouse?*', async (route) => {
    if (++requestCount === 1) await gate
    await route.fulfill({ json: [] })
  })
  await page.goto('/tests/e2e/fixtures/movement-dictionary-reuse.html?mode=race')
  await page.getByRole('button', { name: '打开表单' }).click()
  const dialog = page.getByRole('dialog')
  await expect(dialog).toBeVisible()
  await expect.poll(() => requestCount).toBe(1)
  await dialog.getByRole('button', { name: 'Close this dialog', exact: true }).click()
  await expect(dialog).toBeHidden()
  await page.getByRole('button', { name: '打开表单' }).click()
  await expect(dialog).toHaveAccessibleName('采购入库名称 · 测试仓库 2')
  const oldResponse = page.waitForResponse((response) =>
    new URL(response.url()).pathname.endsWith('/mdm_warehouse')
  )
  release()
  await (await oldResponse).finished()
  await page.evaluate(
    () =>
      new Promise<void>((resolve) => {
        requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
      })
  )
  await expect(dialog).toHaveAccessibleName('采购入库名称 · 测试仓库 2')
})
