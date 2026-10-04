import { mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { expect, test } from '@playwright/test'
import ExcelJS from 'exceljs'
import { mockApplicationMenus } from './support/menu-rpc'
import { tenantId, meta, installFixtures } from './support/inventory-fixtures'

for (const scenario of [
  {
    path: 'count-business/count-gain',
    name: 'WmsCountGain',
    title: '盘盈单',
    table: 'wms_count_adjustment_list',
    kind: 'gain'
  },
  {
    path: 'count-business/count-loss',
    name: 'WmsCountLoss',
    title: '盘亏单',
    table: 'wms_count_adjustment_list',
    kind: 'loss'
  },
  {
    path: 'transfer-business/transfer-request',
    name: 'WmsTransfer',
    title: '调拨申请单',
    table: 'wms_transfer_request_list',
    kind: ''
  },
  {
    path: 'production-inout/production-issue',
    name: 'WmsProductionIssue',
    title: '生产领料单',
    table: 'wms_production_material_list',
    kind: 'issue'
  },
  {
    path: 'production-inout/production-return',
    name: 'WmsProductionReturn',
    title: '生产退料单',
    table: 'wms_production_material_list',
    kind: 'return'
  },
  {
    path: 'initialization/initial-sales-outbound',
    name: 'WmsInitialSalesOutbound',
    title: '期初销售出库单',
    table: 'wms_sales_document_list',
    kind: 'initial_outbound'
  },
  {
    path: 'initialization/initial-sales-return',
    name: 'WmsInitialSalesReturn',
    title: '期初销售退货单',
    table: 'wms_sales_document_list',
    kind: 'initial_return'
  },
  {
    path: 'initialization/initial-purchase-inbound',
    name: 'WmsInitialPurchaseInbound',
    title: '期初采购入库单',
    table: 'wms_purchase_document_list',
    kind: 'initial_inbound'
  },
  {
    path: 'initialization/initial-purchase-return',
    name: 'WmsInitialPurchaseReturn',
    title: '期初采购退料单',
    table: 'wms_purchase_document_list',
    kind: 'initial_return'
  },
  {
    path: 'outbound-business/outbound-request',
    name: 'WmsIssueRequest',
    title: '出库申请单',
    table: 'wms_issue_request_list',
    kind: ''
  }
]) {
  test(`${scenario.title}跨页导出保留展示模式与列表状态`, async ({ page }) => {
    test.setTimeout(180_000)
    await installFixtures(page)
    const menu = {
      id: `export-${scenario.name}`,
      parentId: null,
      name: scenario.name,
      path: `/wms/${scenario.path}`,
      component: `/wms/${scenario.path}`,
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
          { code: 'wms', name: 'WMS仓储管理', baseUrl: '/wms/' }
        ]
      })
    )
    await mockApplicationMenus(page, { wms: [menu, ...buttons] })
    const rows = Array.from({ length: 1002 }, (_, index) => ({
      line_id: `line-${index}`,
      document_id: `document-${Math.floor(index / 2)}`,
      tenant_id: tenantId,
      document_no: `EXPORT-${String(Math.floor(index / 2)).padStart(4, '0')}`,
      line_no: (index % 2) + 1,
      business_date: '2026-10-02',
      application_date: '2026-10-02',
      status: 'draft',
      material_code: `M-${index}`,
      material_description: '分页导出物料',
      specification_model: '测试规格',
      kind: scenario.kind,
      quantity: 1,
      base_quantity: 1,
      book_quantity: 1,
      counted_quantity: 2,
      variance_quantity: 1,
      amount: 1
    }))
    const offsets: number[] = []
    const issueRequest = scenario.table === 'wms_issue_request_list'
    const records = issueRequest
      ? rows
          .filter((_, index) => index % 2 === 0)
          .map((row) => ({
            ...row,
            id: row.document_id,
            request_type: 'material',
            material_codes: '单据汇总编码',
            material_descriptions: '单据汇总物料'
          }))
      : rows
    if (issueRequest) {
      await page.route('**/rest/v1/wms_issue_request_line?*', (route) => {
        const params = new URL(route.request().url()).searchParams
        const ids = new Set(
          (params.get('request_id') || '').slice(4, -1).replaceAll('"', '').split(',')
        )
        const offset = Number(params.get('offset') || 0)
        const limit = Number(params.get('limit') || 500)
        const lines = rows
          .filter((row) => ids.has(row.document_id))
          .map((row) => ({
            id: row.line_id,
            request_id: row.document_id,
            requested_quantity: 1,
            issued_quantity: 0,
            material: { material_code: row.material_code, material_name: row.material_description }
          }))
        return route.fulfill({ json: lines.slice(offset, offset + limit) })
      })
    }
    await page.route(`**/rest/v1/${scenario.table}?*`, (route) => {
      const params = new URL(route.request().url()).searchParams
      if (scenario.kind) expect(params.get('kind')).toBe(`eq.${scenario.kind}`)
      const offset = Number(params.get('offset') || 0)
      const limit = Math.min(Number(params.get('limit') || 1000), 1000)
      offsets.push(offset)
      const data = records.slice(offset, offset + limit)
      return route.fulfill({
        status: 200,
        headers: {
          'content-range': `${offset}-${offset + data.length - 1}/${records.length}`,
          'access-control-expose-headers': 'content-range'
        },
        json: data
      })
    })
    await page.goto(`#/wms/${scenario.path}`, { waitUntil: 'domcontentloaded' })
    await expect(page.getByRole('heading', { name: scenario.title, exact: true })).toBeVisible({
      timeout: 120_000
    })
    for (const mode of ['按单据', '按明细']) {
      await page.locator('.el-radio-button').filter({ hasText: mode }).click()
      await expect(page.getByRole('radio', { name: mode, exact: true })).toBeChecked()
      const body = page.locator('.el-table__body-wrapper').first()
      await expect(body).toContainText('EXPORT-0000')
      await expect(body).toContainText(
        mode === '按明细' ? '分页导出物料' : issueRequest ? '单据汇总物料' : '共 2 项物料'
      )
      const before = await body.innerText()
      offsets.length = 0
      const downloadPromise = page.waitForEvent('download')
      await page.getByRole('button', { name: '导出当前范围', exact: true }).click()
      const download = await downloadPromise
      const downloadPath = await download.path()
      expect(downloadPath).not.toBeNull()
      const workbook = new ExcelJS.Workbook()
      await workbook.xlsx.readFile(downloadPath!)
      const sheet = workbook.worksheets[0]
      expect(sheet.rowCount).toBe(mode === '按单据' ? 502 : 1003)
      expect(sheet.getCell('A2').text).toBe('EXPORT-0000')
      expect(sheet.getCell(`A${sheet.rowCount}`).text).toBe('EXPORT-0500')
      expect(offsets).toContain(issueRequest ? 500 : 1000)
      if (issueRequest && mode === '按明细') {
        expect(new Set(sheet.getColumn(6).values.slice(2)).size).toBe(1002)
      }
      await expect.poll(() => body.innerText()).toBe(before)
    }
  })
}

test('初始库存单带出默认组织与所属功能类型', async ({ page }, testInfo) => {
  test.setTimeout(180_000)
  await installFixtures(page)
  const root = {
    id: 'wms-stock-root',
    parentId: null,
    name: 'WmsWarehouseManagement',
    path: '/wms',
    component: '/index/index',
    type: 'folder',
    sort: 1,
    meta: meta('WMS仓储管理')
  }
  const folder = {
    id: 'wms-stock-folder',
    parentId: root.id,
    name: 'WmsInitialization',
    path: 'initialization',
    component: '',
    type: 'folder',
    sort: 1,
    meta: meta('初始化')
  }
  const menu = {
    id: 'stock-menu',
    parentId: folder.id,
    name: 'WmsInitialStock',
    path: 'initial-stock',
    component: '/wms/initialization/initial-stock',
    type: 'menu',
    sort: 1,
    meta: meta('初始库存单')
  }
  const buttons = ['View', 'Add', 'Copy', 'Edit', 'Delete', 'Export'].map((action) => ({
    id: `wms-stock-${action}`,
    parentId: menu.id,
    name: `WmsInitialStock:${action}`,
    path: '',
    component: '',
    type: 'button',
    sort: 1,
    meta: meta(action),
    children: []
  }))
  await page.route('**/rest/v1/rpc/get_accessible_applications', (route) =>
    route.fulfill({
      json: [
        { code: 'platform', name: '测试平台', baseUrl: '/' },
        { code: 'wms', name: 'WMS仓储管理', baseUrl: '/wms/' }
      ]
    })
  )
  await mockApplicationMenus(page, { wms: [root, folder, menu, ...buttons] })
  await page.route('**/rest/v1/sys_menu?*', (route) => route.fulfill({ json: { id: menu.id } }))
  await page.route('**/rest/v1/mdm_organization?*', (route) =>
    route.fulfill({
      json: [
        {
          id: 'default-stock-org',
          tenant_id: tenantId,
          parent_id: null,
          organization_code: 'DEFAULT-ORG',
          organization_name: '默认库存组织',
          organization_type: 'company',
          status: '1',
          sort: 1,
          is_system: false
        }
      ]
    })
  )
  await page.route('**/rest/v1/wms_inventory_initialization?*', (route) =>
    route.fulfill({
      json: [
        {
          organization_id: 'default-stock-org',
          enabled_on: '2026-10-02',
          is_default: true,
          initialization_closed_at: null
        }
      ]
    })
  )
  await page.route('**/rest/v1/wms_initial_stock_document?*', (route) =>
    route.fulfill({ status: 200, headers: { 'content-range': '*/0' }, json: [] })
  )
  await page.route('**/rest/v1/mdm_document_type?*', (route) =>
    route.fulfill({
      json: [
        {
          id: 'initial-document-type',
          tenant_id: tenantId,
          menu_ids: ['stock-menu'],
          document_type_code: 'WMS_INITIAL_STOCK',
          document_type_name: '标准初始库存单',
          is_default: true,
          enabled: true
        }
      ]
    })
  )
  await page.route('**/rest/v1/mdm_business_type?*', (route) =>
    route.fulfill({
      json: [
        {
          id: 'initial-business-type',
          tenant_id: tenantId,
          document_type_id: 'initial-document-type',
          menu_ids: ['stock-menu'],
          business_type_code: 'WMS_INITIAL_STOCK',
          business_type_name: '初始化库存',
          is_default: true,
          enabled: true
        }
      ]
    })
  )
  await page.goto('#/wms/initialization/initial-stock', { waitUntil: 'domcontentloaded' })
  await expect(page.getByRole('heading', { name: '初始库存单', exact: true })).toBeVisible({
    timeout: 120_000
  })
  await page.getByRole('button', { name: '新增初始库存单' }).click()
  const drawer = page.locator('.el-drawer:visible')
  await expect(drawer.getByText('默认库存组织')).toBeVisible()
  await expect(drawer.getByText('标准初始库存单')).toBeVisible()
  await expect(drawer.getByText('初始化库存')).toBeVisible()
  await expect(drawer.getByText('新增', { exact: true })).toBeVisible()
  await expect(drawer.getByText('复制', { exact: true })).toBeVisible()
  await expect(drawer.getByText('编制', { exact: true })).toBeVisible()
  await expect(drawer.getByText('删除', { exact: true })).toBeVisible()
  await expect(drawer.getByText('序列号', { exact: true })).toBeVisible()
  const visualDir = join(process.cwd(), '.artifacts', 'wms-visual', testInfo.project.name)
  mkdirSync(visualDir, { recursive: true })
  await page.waitForTimeout(350)
  await page.screenshot({ path: join(visualDir, 'wms-initial-stock-defaults.png'), fullPage: true })
  await drawer.getByRole('button', { name: '取消', exact: true }).click()
  await expect(drawer).not.toBeVisible()

  const documents = Array.from({ length: 501 }, (_, index) => ({
    id: `export-document-${index}`,
    tenant_id: tenantId,
    document_no: `EXPORT-${String(index).padStart(4, '0')}`,
    business_date: '2026-10-02',
    status: 'draft',
    lines: [0, 1].map((line) => ({
      id: `export-line-${index}-${line}`,
      opening_quantity: index + line + 1,
      material: { code: `M-${index}-${line}`, name: '导出验证物料' }
    }))
  }))
  const offsets: number[] = []
  await page.route('**/rest/v1/wms_initial_stock_document?*', (route) => {
    const params = new URL(route.request().url()).searchParams
    const offset = Number(params.get('offset') || 0)
    const limit = Number(params.get('limit') || 500)
    offsets.push(offset)
    const rows = documents.slice(offset, offset + limit)
    return route.fulfill({
      status: 200,
      headers: {
        'content-range': `${offset}-${offset + rows.length - 1}/${documents.length}`,
        'access-control-expose-headers': 'content-range'
      },
      json: rows
    })
  })
  for (const mode of ['按单据', '按明细']) {
    if (mode === '按明细') {
      await page.locator('.el-radio-button').filter({ hasText: mode }).click()
      await expect(page.getByRole('radio', { name: mode, exact: true })).toBeChecked()
    }
    offsets.length = 0
    const downloadPromise = page.waitForEvent('download')
    await page.getByRole('button', { name: '导出筛选结果', exact: true }).click()
    const download = await downloadPromise
    const downloadPath = await download.path()
    expect(downloadPath).not.toBeNull()
    const workbook = new ExcelJS.Workbook()
    await workbook.xlsx.readFile(downloadPath!)
    const sheet = workbook.worksheets[0]
    expect(sheet.rowCount).toBe(1003)
    expect(sheet.getCell('A2').text).toBe('EXPORT-0000')
    expect(sheet.getCell('A1003').text).toBe('EXPORT-0500')
    expect(new Set(sheet.getColumn(4).values.slice(2)).size).toBe(1002)
    expect(offsets).toContain(500)
  }
})
