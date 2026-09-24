import { mkdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { expect, test, type Page } from '@playwright/test'

const tenantId = '7529f951-938e-4e2c-ac0d-316c136ae1f9'
const warehouseId = 'd97f5bc1-73c4-4617-9225-b0af0327875f'
const zoneId = '1b36951f-7564-4c4a-a88f-cc2d41645c5e'
const binId = 'ed276e75-d9d4-4742-a667-d758731d15f8'
const materialId = 'c08915d0-75c9-43b3-9c7d-359e0009f106'
const pages = [
  ['MdmWarehouseDefinition', 'warehouse-definition', 'warehouse', '仓库定义'],
  ['MdmSupplyChainCodeRule', 'supply-chain-code-rule', 'configuration', '供应链编码规则'],
  ['MdmOutboundRule', 'outbound-rule', 'configuration', '出库规则配置'],
  ['MdmWarehouseZone', 'zone', 'zone', '库区管理'],
  ['MdmWarehouseBin', 'bin', 'bin', '库位管理'],
  ['MdmInventoryBatch', 'batch', 'batch', '库存批次'],
  ['MdmInventoryReservation', 'reservation', 'reservation', '库存预留'],
  ['MdmInventoryPackage', 'package', 'package', '垛包管理'],
  ['MdmInventorySerial', 'serial', 'serial', '序列号']
] as const

const meta = (title: string) => ({ title, roles: ['R_SUPER'], is_enable: true, is_hide: false })
const dictionaryItems: Record<string, [string, string, string][]> = {
  mdmWarehouseType: [
    ['raw_material', '原料仓', 'primary'],
    ['finished', '成品仓', 'success']
  ],
  mdmWarehouseBusinessScope: [
    ['picking', '拣货', 'primary'],
    ['availability', '显示可用库存', 'success'],
    ['warning', '库存预警', 'warning']
  ],
  mdmWarehouseBinType: [
    ['stack', '垛位', 'primary'],
    ['shelf', '货架货位', 'info']
  ],
  mdmWarehouseBinStatus: [
    ['available', '可存', 'success'],
    ['locked', '锁定', 'warning'],
    ['disabled', '停用', 'info']
  ],
  mdmInventoryReservationStatus: [
    ['active', '预留中', 'primary'],
    ['released', '已释放', 'info']
  ],
  mdmInventorySerialStatus: [['in_stock', '在库', 'success']]
}
const dictionaryRows = Object.entries(dictionaryItems).flatMap(([type, values]) =>
  values.map(([value, label, tagType], index) => ({
    id: `${type}-${value}`,
    type_id: type,
    code: value,
    label,
    value,
    sort: index + 1,
    color: '',
    tag_type: tagType,
    remark: '',
    dict_type_table: { code: type, name: type }
  }))
)
const warehouse = {
  id: warehouseId,
  tenant_id: tenantId,
  warehouse_code: 'RAW-A',
  warehouse_name: '原料一仓',
  warehouse_type: 'raw_material',
  business_scopes: ['picking', 'availability', 'warning'],
  enable_locations: true,
  enable_zones: true,
  single_sku_per_bin: false,
  status: 'enabled',
  sort: 10
}
const zone = {
  id: zoneId,
  tenant_id: tenantId,
  warehouse_id: warehouseId,
  zone_code: 'BOARD',
  zone_name: '板材区',
  category_id: null,
  category: null,
  purpose: 'storage',
  allow_mix: true,
  requires_inspection: false,
  allow_lock: true,
  abnormal: false,
  status: 'enabled',
  sort: 10
}
const zoneRows = [
  zone,
  {
    ...zone,
    id: '1b36951f-7564-4c4a-a88f-cc2d41645c5f',
    zone_code: 'COIL',
    zone_name: '彩卷区',
    sort: 20
  },
  {
    ...zone,
    id: '1b36951f-7564-4c4a-a88f-cc2d41645c60',
    zone_code: 'INSPECTION',
    zone_name: '待检区',
    abnormal: true,
    sort: 30
  },
  {
    ...zone,
    id: '1b36951f-7564-4c4a-a88f-cc2d41645c61',
    zone_code: 'CLOSED',
    zone_name: '停用区',
    status: 'disabled',
    sort: 40
  }
]
const bin = {
  id: binId,
  tenant_id: tenantId,
  warehouse_id: warehouseId,
  zone_id: zoneId,
  parent_bin_id: null,
  bin_code: 'RAW-A-BOARD-01',
  bin_name: '一号垛位',
  bin_type: 'stack',
  shelf_code: null,
  level_no: null,
  column_no: null,
  max_weight_kg: 1000,
  max_area_sqm: 80,
  max_quantity: 100,
  fixed_material_id: null,
  allow_mix: true,
  supports_serial: false,
  status: 'available',
  sort: 10
}
const binRows = [
  bin,
  {
    ...bin,
    id: 'ed276e75-d9d4-4742-a667-d758731d15f9',
    bin_code: 'RAW-A-SH-1-1',
    bin_name: '货架 1-1',
    bin_type: 'shelf',
    shelf_code: 'A01',
    level_no: 1,
    column_no: 1,
    sort: 20
  },
  {
    ...bin,
    id: 'ed276e75-d9d4-4742-a667-d758731d15fa',
    bin_code: 'RAW-A-SH-1-2',
    bin_name: '定容货位',
    bin_type: 'shelf',
    shelf_code: 'A01',
    level_no: 1,
    column_no: 2,
    fixed_material_id: materialId,
    sort: 30
  },
  {
    ...bin,
    id: 'ed276e75-d9d4-4742-a667-d758731d15fb',
    bin_code: 'RAW-A-SH-2-1',
    bin_name: '锁定货位',
    bin_type: 'shelf',
    shelf_code: 'A01',
    level_no: 2,
    column_no: 1,
    status: 'locked',
    sort: 40
  },
  {
    ...bin,
    id: 'ed276e75-d9d4-4742-a667-d758731d15fc',
    bin_code: 'RAW-A-SH-2-2',
    bin_name: '停用货位',
    bin_type: 'shelf',
    shelf_code: 'A01',
    level_no: 2,
    column_no: 2,
    status: 'disabled',
    sort: 50
  }
]
const material = {
  id: materialId,
  tenant_id: tenantId,
  material_code: 'RAW-001',
  material_name: '岩棉板',
  specification_model: '1200×600×100',
  material_type: 'ROH',
  category_id: null,
  gross_weight: 5
}
const batch = {
  id: 'c243b98a-c75e-45dd-802f-4c5b699363b2',
  tenant_id: tenantId,
  warehouse_id: warehouseId,
  bin_id: binId,
  material_id: materialId,
  batch_no: 'B-20260924-01',
  work_order_id: null,
  pack_id: null,
  quantity: 12,
  area_sqm: 8.64,
  length_mm: 1200,
  width_mm: 600,
  thickness_mm: 100,
  unit_cost: 80,
  received_at: '2026-06-01T08:00:00Z',
  last_movement_at: '2026-06-01T08:00:00Z',
  status: 'normal',
  material,
  warehouse: { id: warehouseId, warehouse_code: 'RAW-A', warehouse_name: '原料一仓' },
  bin: { id: binId, bin_code: 'RAW-A-BOARD-01', bin_name: '一号垛位', zone_id: zoneId }
}

function inventoryMenu() {
  const rootId = 'wms-test-root'
  const folderId = 'wms-test-inventory'
  return {
    id: rootId,
    parentId: null,
    name: 'MdmMasterData',
    path: '/mdm',
    component: '/index/index',
    type: 'folder',
    sort: 1,
    meta: meta('MDM主数据'),
    children: [
      {
        id: folderId,
        parentId: rootId,
        name: 'MdmInventoryMaster',
        path: 'inventory-master',
        component: '',
        type: 'folder',
        sort: 1,
        meta: meta('库存主数据'),
        children: pages.map(([name, path, component, title], index) => ({
          id: `wms-test-${name}`,
          parentId: folderId,
          name,
          path,
          component: `/mdm/inventory/${component}`,
          type: 'menu',
          sort: index,
          meta: meta(title),
          children: [
            'View',
            'Add',
            'Edit',
            'Delete',
            'Sort',
            'Generate',
            'Receive',
            'Issue',
            'Transfer',
            'Configure',
            'Release',
            'Assign',
            'Unassign'
          ].map((action) => ({
            id: `wms-test-${name}-${action}`,
            parentId: `wms-test-${name}`,
            name: `${name}:${action}`,
            path: '',
            component: '',
            type: 'button',
            sort: 0,
            meta: meta(action),
            children: []
          }))
        }))
      }
    ]
  }
}

async function installFixtures(page: Page): Promise<void> {
  const state = JSON.parse(readFileSync('playwright/.auth/user.json', 'utf8')) as {
    origins: { localStorage: { name: string; value: string }[] }[]
  }
  const entries = state.origins.flatMap((origin) => origin.localStorage)
  await page.addInitScript((entries) => {
    for (const entry of entries) localStorage.setItem(entry.name, entry.value)
    for (const key of Object.keys(localStorage)) {
      if (!/^sb-.*-auth-token$/.test(key)) continue
      const session = JSON.parse(localStorage.getItem(key) || '{}')
      session.expires_at = Math.floor(Date.now() / 1000) + 3600
      session.expires_in = 3600
      const [header, payload, signature] = String(session.access_token || '').split('.')
      if (header && payload && signature) {
        const claims = JSON.parse(atob(payload.replace(/-/g, '+').replace(/_/g, '/')))
        claims.iat = Math.floor(Date.now() / 1000)
        claims.exp = claims.iat + 3600
        const freshPayload = btoa(JSON.stringify(claims))
          .replace(/\+/g, '-')
          .replace(/\//g, '_')
          .replace(/=+$/, '')
        session.access_token = `${header}.${freshPayload}.${signature}`
      }
      localStorage.setItem(key, JSON.stringify(session))
    }
  }, entries)
  const tenant = { id: tenantId, tenant_code: 'DEMO', tenant_name: '示例工厂' }
  const menu = inventoryMenu()
  const flat: object[] = []
  const walk = (
    node:
      | typeof menu
      | (typeof menu.children)[number]
      | (typeof menu.children)[number]['children'][number]
  ) => {
    flat.push({ ...node, children: undefined })
    for (const child of node.children) walk(child as typeof menu)
  }
  walk(menu)
  await page.route('**/rest/v1/**', (route) => route.fulfill({ json: [] }))
  await page.route('**/auth/v1/user', (route) =>
    route.fulfill({
      json: {
        id: '705ddd8d-4959-4dc1-aeb0-08caed7ab51a',
        aud: 'authenticated',
        role: 'authenticated'
      }
    })
  )
  await page.route('**/rest/v1/sys_user?*', (route) =>
    route.fulfill({
      json: {
        id: 'wms-test-user',
        auth_user_id: '705ddd8d-4959-4dc1-aeb0-08caed7ab51a',
        user_name: '测试用户',
        user_email: 'wms@example.invalid',
        user_type: '1',
        user_roles: ['R_SUPER'],
        status: '1',
        tenant_id: tenantId,
        tenant
      }
    })
  )
  await page.route('**/rest/v1/sys_param?*', (route) => route.fulfill({ json: [] }))
  await page.route('**/rest/v1/sys_dictionary?*', (route) => {
    const filter = new URL(route.request().url()).searchParams.get('dict_type_table.code')
    const type = filter?.replace(/^eq\./, '')
    return route.fulfill({
      json: type
        ? dictionaryRows.filter((row) => row.dict_type_table.code === type)
        : dictionaryRows
    })
  })
  await page.route('**/rest/v1/sys_tenant?*', (route) => route.fulfill({ json: [tenant] }))
  await page.route('**/rest/v1/rpc/current_is_super', (route) => route.fulfill({ json: true }))
  await page.route('**/rest/v1/rpc/get_accessible_applications', (route) =>
    route.fulfill({
      json: [
        { code: 'platform', name: '测试平台', baseUrl: '/' },
        { code: 'mdm', name: 'MDM主数据', baseUrl: '/mdm/' }
      ]
    })
  )
  await page.route('**/rest/v1/rpc/get_menus_for_current_application', (route) =>
    route.fulfill({
      json:
        (route.request().postDataJSON() as { p_app_code?: string }).p_app_code === 'mdm'
          ? { flat, tree: [menu] }
          : { flat: [], tree: [] }
    })
  )
  await page.route('**/rest/v1/rpc/mdm_list_warehouses_secure', (route) =>
    route.fulfill({
      json: {
        data: [warehouse],
        total: 1,
        groups: [],
        overview: { total: 1, enabled: 1, locationEnabled: 1, managed: 1 }
      }
    })
  )
  await page.route('**/rest/v1/mdm_warehouse?*', (route) => route.fulfill({ json: [warehouse] }))
  await page.route('**/rest/v1/mdm_warehouse_zone?*', (route) => route.fulfill({ json: zoneRows }))
  await page.route('**/rest/v1/mdm_warehouse_bin?*', (route) => route.fulfill({ json: binRows }))
  await page.route('**/rest/v1/wms_inventory_batch?*', (route) =>
    route.fulfill({
      json: [batch],
      headers: { 'content-range': '0-0/1' }
    })
  )
  await page.route('**/rest/v1/wms_inventory_policy?*', (route) =>
    route.fulfill({
      json: [{ tenant_id: tenantId, stale_days: 90, auto_reserve_on_release: false }]
    })
  )
  await page.route('**/rest/v1/rpc/wms_storage_overview_secure', (route) =>
    route.fulfill({
      json: {
        staleDays: 90,
        zones: [
          {
            zoneId,
            materialCount: 1,
            amount: 960,
            unpricedCount: 0,
            staleMaterialCount: 1,
            staleAmount: 960,
            staleUnpricedCount: 0,
            quantity: 12
          }
        ],
        bins: [
          {
            binId,
            materialCount: 1,
            amount: 960,
            unpricedCount: 0,
            staleMaterialCount: 1,
            staleAmount: 960,
            staleUnpricedCount: 0,
            quantity: 12
          }
        ]
      }
    })
  )
  await page.route('**/rest/v1/rpc/wms_list_reservations_secure', (route) =>
    route.fulfill({
      json: {
        total: 2,
        data: [
          {
            id: '93bd7d22-37db-4a20-98fb-e68fd2abe5b1',
            tenantId,
            workOrderId: '39b66f7c-3b4c-4b7d-b849-5ee7cb1d558a',
            workOrderNo: 'DEMO-WMS-001',
            materialId,
            materialCode: 'RAW-001',
            materialName: '岩棉板',
            warehouseId,
            warehouseName: '原料一仓',
            binId,
            binCode: 'RAW-A-BOARD-01',
            reservedQuantity: 3,
            status: 'active',
            remark: '演示工单锁料',
            createTime: '2026-09-24T08:00:00Z'
          },
          {
            id: '93bd7d22-37db-4a20-98fb-e68fd2abe5b2',
            tenantId,
            workOrderId: '39b66f7c-3b4c-4b7d-b849-5ee7cb1d558a',
            workOrderNo: 'DEMO-WMS-001',
            materialId,
            materialCode: 'RAW-001',
            materialName: '岩棉板',
            warehouseId,
            warehouseName: '原料一仓',
            binId,
            binCode: 'RAW-A-BOARD-01',
            reservedQuantity: 2,
            status: 'released',
            remark: '演示已释放',
            createTime: '2026-09-23T08:00:00Z'
          }
        ]
      }
    })
  )
  await page.route('**/rest/v1/rpc/wms_list_packages_secure', (route) =>
    route.fulfill({
      json: {
        total: 1,
        data: [
          {
            id: 'cc2ad53c-a052-43c7-9edb-5a02be2586d4',
            tenantId,
            packNo: 'DEMO-WMS-PACK-01',
            workOrderId: '39b66f7c-3b4c-4b7d-b849-5ee7cb1d558a',
            workOrderNo: 'DEMO-WMS-001',
            constructionNo: '演示施工号',
            materialId,
            itemCount: 3,
            pieceCount: 24,
            placementId: 'e9775ba4-cbb0-4708-999c-fe63fe96ad4b',
            warehouseId,
            binId
          }
        ]
      }
    })
  )
  await page.route('**/rest/v1/rpc/wms_list_serials_secure', (route) =>
    route.fulfill({
      json: {
        total: 1,
        data: [
          {
            id: '76717031-6317-4fd5-846a-f421f4b1ea58',
            tenantId,
            serialNo: 'DEMO-WMS-SN-001',
            workOrderId: '39b66f7c-3b4c-4b7d-b849-5ee7cb1d558a',
            workOrderNo: 'DEMO-WMS-001',
            materialId,
            materialCode: 'RAW-001',
            materialName: '岩棉板',
            specificationModel: '1200×600×100',
            materialSource: 'purchase',
            materialType: 'ROH',
            batchId: batch.id,
            status: 'in_stock',
            warehouseId,
            warehouseName: '原料一仓',
            binId,
            binCode: 'RAW-A-BOARD-01',
            remark: '演示序列号',
            createTime: '2026-09-24T08:00:00Z'
          }
        ]
      }
    })
  )
  await page.route('**/rest/v1/rpc/wms_work_order_options_secure', (route) =>
    route.fulfill({ json: [] })
  )
  await page.route('**/rest/v1/mdm_material?*', (route) => route.fulfill({ json: [material] }))
}

test('库存主数据布局与库位交互', async ({ page }, testInfo) => {
  test.setTimeout(420_000)
  const visualDir = join(process.cwd(), '.artifacts', 'wms-visual', testInfo.project.name)
  mkdirSync(visualDir, { recursive: true })
  await installFixtures(page)
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error.message))
  const selectedPages = process.env.WMS_E2E_PAGE
    ? pages.filter(([, path]) => path === process.env.WMS_E2E_PAGE)
    : pages
  for (const [, path, , title] of selectedPages) {
    await page.goto(`/#/mdm/inventory-master/${path}`, { waitUntil: 'domcontentloaded' })
    await expect(page.getByRole('heading', { name: title, exact: true })).toBeVisible({
      timeout: 60_000
    })
    await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 30_000 })
    const themeTipDismiss = page.getByText('知道了', { exact: true })
    if (await themeTipDismiss.isVisible()) await themeTipDismiss.click()
    const overflow = await page.evaluate(() => ({
      viewport: document.documentElement.clientWidth,
      content: document.documentElement.scrollWidth
    }))
    expect(overflow.content, `${title} 出现横向溢出`).toBeLessThanOrEqual(overflow.viewport + 1)
    await page.screenshot({ path: join(visualDir, `mdm-${path}.png`), fullPage: true })
    if (path === 'zone' || path === 'bin') {
      await expect(page.getByRole('button', { name: '进入专注模式' })).toHaveCount(0)
      await expect(page.getByRole('switch', { name: '进入专注模式' })).toHaveCount(0)
      await expect(page.locator('.art-section-card .el-scrollbar').first()).toBeVisible()
    } else {
      await expect(
        page.locator('.business-workspace-header').getByText('专注模式', { exact: true })
      ).toBeVisible()
      await page.getByRole('switch', { name: '进入专注模式' }).locator('..').click()
      await expect(page.getByRole('heading', { name: title, exact: true })).toBeHidden()
      await page.screenshot({ path: join(visualDir, `mdm-${path}-focus.png`), fullPage: true })
      await page.keyboard.press('Escape')
      await expect(page.getByRole('heading', { name: title, exact: true })).toBeVisible()
    }
    if (path === 'bin') {
      const tile = page.getByRole('button', { name: /^一号垛位，/ })
      await tile.hover()
      await expect(page.getByText(/库存金额.*960/)).toBeVisible()
      await expect(page.getByText(/呆滞物料 1 种/)).toBeVisible()
      await tile.dblclick()
      await expect(page.getByText('B-20260924-01', { exact: true })).toBeVisible()
    }
  }
  expect(errors).toEqual([])
})
