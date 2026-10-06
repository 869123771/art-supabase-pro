import { expect, test } from '@playwright/test'
import { installFixtures, meta } from './support/inventory-fixtures'
import { mockApplicationMenus } from './support/menu-rpc'

const scenarios = [
  ['stock', 'stock', 'WmsStock', '即时库存'],
  ['movement', 'inventory-ledger', 'WmsInventoryLedger', '库存流水'],
  ['ledger', 'stock-ledger', 'WmsStockLedger', '库存台账'],
  ['receipt-issue', 'material-receipt-issue', 'WmsMaterialReceiptIssue', '物料收发明细表']
] as const

for (const [kind, segment, name, title] of scenarios) {
  test(`${title}查询失败恢复、空态与专注模式`, async ({ page }, testInfo) => {
    test.setTimeout(90_000)
    await installFixtures(page)
    await page.route('**/rest/v1/rpc/get_accessible_applications', (route) =>
      route.fulfill({
        json: [
          { code: 'platform', name: '测试平台', baseUrl: '/' },
          { code: 'wms', name: 'WMS仓储管理', baseUrl: '/wms/' }
        ]
      })
    )
    const root = {
      id: 'wms-root',
      parentId: null,
      name: 'WmsWarehouseManagement',
      path: '/wms',
      component: '/index/index',
      type: 'folder',
      sort: 1,
      meta: meta('WMS仓储管理')
    }
    const path = `inventory-trace/${segment}`
    const menu = {
      id: 'report-menu',
      parentId: root.id,
      name,
      path,
      component: `/wms/${path}`,
      type: 'menu',
      sort: 1,
      meta: meta(title)
    }
    await mockApplicationMenus(page, {
      wms: [
        root,
        menu,
        {
          id: 'report-view',
          parentId: menu.id,
          name: `${name}:View`,
          path: '',
          component: '',
          type: 'button',
          sort: 1,
          meta: meta('查看')
        }
      ]
    })
    let state: 'data' | 'error' | 'empty' = 'data'
    const requests: Record<string, unknown>[] = []
    const row = {
      id: 'report-test',
      batch_id: 'batch-test',
      material_code: 'TEST-MAT',
      material_name: '测试库存物料',
      warehouse_id: 'warehouse-test',
      warehouse_name: '测试仓库',
      inventory_quantity: 1,
      opening_quantity: 0,
      inbound_quantity: 1,
      outbound_quantity: 0,
      closing_quantity: 1,
      document_type: 'purchase_in',
      document_no: 'TEST-PURCHASE-001'
    }
    await page.route('**/rest/v1/rpc/wms_inventory_report_secure', (route) => {
      requests.push(route.request().postDataJSON())
      return route.fulfill(
        state === 'error'
          ? { status: 503, json: { message: '测试报表读取失败', code: 'XX000' } }
          : {
              json: {
                data: state === 'data' ? [row] : [],
                total: state === 'data' ? 1 : 0,
                navigation: []
              }
            }
      )
    })
    await page.goto(`#/wms/${path}`)
    if (await page.getByRole('button', { name: '知道了', exact: true }).isVisible()) {
      await page.getByRole('button', { name: '知道了', exact: true }).click()
    }
    const header = page.locator('.business-workspace-header')
    const table = page.locator('.art-table-query')
    await expect(page.getByText('TEST-MAT', { exact: true })).toBeVisible()
    await page.getByRole('switch', { name: '进入专注模式', exact: true }).locator('..').click()
    await expect(header).toBeHidden()
    await expect(page.locator('.inventory-location-navigator')).toBeVisible()
    await expect(table).toHaveClass(/is-focus-mode/)
    await page.screenshot({ path: testInfo.outputPath('report-focus.png'), animations: 'disabled' })
    await table.getByRole('button', { name: '退出专注模式', exact: true }).scrollIntoViewIfNeeded()
    await page.screenshot({
      path: testInfo.outputPath('report-focus-table.png'),
      animations: 'disabled'
    })
    await page.keyboard.press('Escape')
    await expect(header).toBeVisible()
    await expect(table).not.toHaveClass(/is-focus-mode/)
    const materialCode = page.getByRole('textbox', { name: '物料编码', exact: true })
    await materialCode.fill('TEST-MAT')
    state = 'error'
    await page.getByRole('button', { name: '查询', exact: true }).click()
    await expect(table.getByText('数据加载失败', { exact: true })).toBeVisible()
    await expect(materialCode).toHaveValue('TEST-MAT')
    await table.getByText('数据加载失败', { exact: true }).scrollIntoViewIfNeeded()
    await page.screenshot({ path: testInfo.outputPath('report-error.png'), animations: 'disabled' })
    state = 'data'
    await table.getByRole('button', { name: '重新加载', exact: true }).click()
    await expect(page.getByText('TEST-MAT', { exact: true })).toBeVisible()
    expect(requests.at(-1)?.p_kind).toBe(kind)
    expect(requests.at(-1)?.p_material_code).toBe('TEST-MAT')
    state = 'empty'
    await page.getByRole('button', { name: '查询', exact: true }).click()
    await expect(table.getByText(`当前范围暂无${title}数据`, { exact: true })).toBeVisible()
    await page.getByRole('switch', { name: '进入专注模式', exact: true }).locator('..').click()
    await expect(header).toBeHidden()
    await expect(table.getByText(`当前范围暂无${title}数据`, { exact: true })).toBeVisible()
    await page.getByRole('button', { name: '退出专注模式', exact: true }).click()
    await expect(header).toBeVisible()
    await expect(materialCode).toHaveValue('TEST-MAT')
    expect(
      await page
        .locator('.business-workspace-page')
        .evaluate((node) => node.scrollWidth - node.clientWidth)
    ).toBeLessThanOrEqual(1)
    await table.getByText(`当前范围暂无${title}数据`, { exact: true }).scrollIntoViewIfNeeded()
    await page.screenshot({
      path: testInfo.outputPath('report-empty-restored.png'),
      animations: 'disabled'
    })
  })
}
