import { expect, test } from '@playwright/test'
import ExcelJS from 'exceljs'
import { installFixtures, meta, tenantId } from './support/inventory-fixtures'
import { mockApplicationMenus } from './support/menu-rpc'

for (const scenario of [
  {
    path: 'sales-management/sales-order',
    name: 'ScmSalesOrder',
    title: '销售订单',
    table: 'scm_sales_document',
    kind: 'sales_order'
  },
  {
    path: 'purchase-management/purchase-order',
    name: 'ScmPurchaseOrder',
    title: '采购订单',
    table: 'scm_purchase_document',
    kind: 'purchase_order'
  }
]) {
  test(`${scenario.title}两种展示模式完整导出跨页数据`, async ({ page }) => {
    test.setTimeout(180_000)
    await installFixtures(page)
    const menu = {
      id: `export-${scenario.name}`,
      parentId: null,
      name: scenario.name,
      path: `/scm/${scenario.path}`,
      component: `/scm/${scenario.path}`,
      type: 'menu',
      sort: 1,
      meta: meta(scenario.title)
    }
    const buttons = ['View', 'Export'].map((action) => ({
      id: `${menu.id}-${action}`,
      parentId: menu.id,
      name: `${scenario.name}:${action}`,
      path: '',
      component: '',
      type: 'button',
      sort: 1,
      meta: meta(action)
    }))
    await page.route('**/rest/v1/rpc/get_accessible_applications', (route) =>
      route.fulfill({
        json: [
          { code: 'platform', name: '测试平台', baseUrl: '/' },
          { code: 'scm', name: 'SCM供应链管理', baseUrl: '/scm/' }
        ]
      })
    )
    await mockApplicationMenus(page, { scm: [menu, ...buttons] })
    const documents = Array.from({ length: 1001 }, (_, index) => ({
      id: `document-${index}`,
      tenant_id: tenantId,
      kind: scenario.kind,
      document_no: `EXPORT-${String(index).padStart(4, '0')}`,
      document_date: '2026-10-04',
      status: 'draft',
      subtotal: 2,
      tax_amount: 0,
      total_amount: 2,
      lines: [0, 1].map((line) => ({
        line_id: `line-${index}-${line}`,
        line_no: line + 1,
        material_code: `M-${index}-${line}`,
        material_description: '跨页导出物料',
        quantity: 1,
        unit_price: 1,
        amount: 1,
        tax_amount: 0,
        total_amount: 1
      }))
    }))
    const offsets: number[] = []
    await page.route(`**/rest/v1/${scenario.table}?*`, (route) => {
      const params = new URL(route.request().url()).searchParams
      expect(params.get('kind')).toBe(`eq.${scenario.kind}`)
      const offset = Number(params.get('offset') || 0)
      const limit = Math.min(Number(params.get('limit') || 1000), 1000)
      offsets.push(offset)
      const data = documents.slice(offset, offset + limit)
      return route.fulfill({
        status: 200,
        headers: {
          'content-range': `${offset}-${offset + data.length - 1}/${documents.length}`,
          'access-control-expose-headers': 'content-range'
        },
        json: data
      })
    })
    await page.goto(`#/scm/${scenario.path}`, { waitUntil: 'domcontentloaded' })
    await expect(page.getByRole('heading', { name: scenario.title, exact: true })).toBeVisible({
      timeout: 120_000
    })
    for (const mode of ['按单据', '按明细']) {
      await page.locator('.el-radio-button').filter({ hasText: mode }).click()
      await expect(page.getByRole('radio', { name: mode, exact: true })).toBeChecked()
      offsets.length = 0
      const downloadPromise = page.waitForEvent('download')
      await page.getByRole('button', { name: '导出', exact: true }).click()
      const path = await (await downloadPromise).path()
      expect(path).not.toBeNull()
      const workbook = new ExcelJS.Workbook()
      await workbook.xlsx.readFile(path!)
      const sheet = workbook.worksheets[0]
      expect(sheet.rowCount).toBe(mode === '按单据' ? 1002 : 2003)
      expect(sheet.getCell('A2').text).toBe('EXPORT-0000')
      expect(sheet.getCell(`A${sheet.rowCount}`).text).toBe('EXPORT-1000')
      expect(offsets).toContain(1000)
    }
  })
}
