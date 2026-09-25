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
  commonBoolean: [
    ['false', '否', 'info'],
    ['true', '是', 'success']
  ],
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
  mdmInventoryMovementType: [
    ['purchase_in', '采购入库', 'primary'],
    ['production_in', '生产入库', 'success'],
    ['other_in', '其他入库', 'info'],
    ['sales_out', '销售出库', 'warning'],
    ['other_out', '其他出库', 'warning'],
    ['transfer', '库存调拨', 'primary']
  ],
  mdmInventoryReservationStatus: [
    ['active', '预留中', 'primary'],
    ['released', '已释放', 'info']
  ],
  mdmInventorySerialStatus: [['in_stock', '在库', 'success']],
  mdmMaterialSource: [['purchase', '采购', 'primary']]
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
  parent_id: null,
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
    id: 'ed276e75-d9d4-4742-a667-d758731d15fd',
    parent_id: 'ed276e75-d9d4-4742-a667-d758731d15f9',
    bin_code: 'RAW-A-SH-1-1-A',
    bin_name: '货架 1-1 子单元',
    bin_type: 'floor',
    shelf_code: null,
    level_no: null,
    column_no: null,
    sort: 25
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
  await page.route('**/rest/v1/mdm_outbound_rule?*', (route) =>
    route.fulfill({
      json: [
        {
          id: 'f4b342d2-d619-48a8-8d24-e67ef208f7a4',
          tenant_id: tenantId,
          rule_code: 'OUT-001',
          rule_name: '先进先出库规则',
          status: 'enabled',
          sorts: [],
          update_time: '2026-09-24T08:00:00Z'
        }
      ],
      headers: { 'content-range': '0-0/1' }
    })
  )
  await page.route('**/rest/v1/mdm_supply_chain_code_rule?*', (route) =>
    route.fulfill({
      json: [
        {
          id: '20b1abda-cc2e-4c47-b859-8c4d4cddf5cd',
          tenant_id: tenantId,
          rule_code: 'CODE-001',
          rule_name: '批号编码规则',
          example_code: 'B20260924001',
          apply_batch: true,
          apply_serial: false,
          apply_tracking: false,
          per_material: true,
          separator: '',
          status: 'enabled',
          segments: [],
          update_time: '2026-09-24T08:00:00Z'
        }
      ],
      headers: { 'content-range': '0-0/1' }
    })
  )
  await page.route('**/rest/v1/wms_inventory_batch?*', (route) =>
    route.fulfill({
      status: 206,
      json: [batch],
      headers: {
        'content-range': '0-0/1',
        'access-control-allow-origin': '*',
        'access-control-expose-headers': 'content-range'
      }
    })
  )
  await page.route('**/rest/v1/wms_inventory_policy?*', (route) =>
    route.fulfill({
      json: [{ tenant_id: tenantId, stale_days: 90, auto_reserve_on_release: true }]
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
  await page.route('**/rest/v1/mdm_material_type?*', (route) =>
    route.fulfill({
      json: [
        {
          id: '8bb1b1cc-51a2-4771-9a69-c4b9b1297d08',
          tenant_id: tenantId,
          type_code: 'ROH',
          type_name: '原材料',
          status: 'enabled'
        }
      ]
    })
  )
}

test('库存主数据布局与库位交互', async ({ page }, testInfo) => {
  test.setTimeout(540_000)
  const visualDir = join(process.cwd(), '.artifacts', 'wms-visual', testInfo.project.name)
  mkdirSync(visualDir, { recursive: true })
  await installFixtures(page)
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error.message))
  const selectedPages = process.env.WMS_E2E_PAGE
    ? pages.filter(([, path]) => path === process.env.WMS_E2E_PAGE)
    : pages
  for (const [, path, , title] of selectedPages) {
    if (path === 'reservation') {
      await page.route('**/rest/v1/rpc/wms_work_order_options_secure', (route) =>
        route.fulfill({
          json: [
            {
              id: 'c0767f00-0000-4000-8000-000000000001',
              tenantId,
              workOrderNo: '可领料测试工单',
              materialId,
              constructionNo: null,
              allowedIssueWarehouseTypes: ['raw_material']
            },
            {
              id: 'c0767f00-0000-4000-8000-000000000002',
              tenantId,
              workOrderNo: '仅成品仓测试工单',
              materialId,
              constructionNo: null,
              allowedIssueWarehouseTypes: ['finished']
            }
          ]
        })
      )
    }
    await page.goto(`/#/mdm/inventory-master/${path}`, { waitUntil: 'domcontentloaded' })
    await expect(page.getByRole('heading', { name: title, exact: true })).toBeVisible({
      timeout: 120_000
    })
    await expect(page.locator('.art-page-view:visible').last()).toHaveCSS('opacity', '1')
    await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 30_000 })
    await expect(page.locator('.art-overlay-loading.is-loading:visible')).toHaveCount(0, {
      timeout: 30_000
    })
    const themeTipDismiss = page.getByText('知道了', { exact: true })
    if (await themeTipDismiss.isVisible()) await themeTipDismiss.click()
    const overflow = await page.evaluate(() => ({
      viewport: document.documentElement.clientWidth,
      content: document.documentElement.scrollWidth
    }))
    expect(overflow.content, `${title} 出现横向溢出`).toBeLessThanOrEqual(overflow.viewport + 1)
    if (path === 'outbound-rule' || path === 'supply-chain-code-rule') {
      const identity = page.locator('.business-table-identity-cell:visible').first()
      await expect(identity.locator('strong')).toBeVisible()
      await expect(identity.locator('small')).toBeVisible()
      const primary = await identity.locator('strong').boundingBox()
      const secondary = await identity.locator('small').boundingBox()
      expect(primary).not.toBeNull()
      expect(secondary).not.toBeNull()
      expect(secondary!.y).toBeGreaterThan(primary!.y)
    }
    await page.screenshot({ path: join(visualDir, `mdm-${path}.png`), fullPage: true })
    if (path === 'zone' || path === 'bin') {
      await expect(page.getByRole('button', { name: '进入专注模式' })).toHaveCount(0)
      await expect(page.getByRole('switch', { name: '进入专注模式' })).toHaveCount(0)
      await expect(page.locator('.art-section-card .el-scrollbar').first()).toBeVisible()
      if (path === 'bin') {
        await expect(page.locator('.art-workspace-splitter')).toHaveCount(2)
        if ((page.viewportSize()?.width ?? 0) > 1200) {
          await expect(page.locator('.art-workspace-splitter .el-splitter-bar')).toHaveCount(2)
          const splitter = page.locator('.art-workspace-splitter').first()
          const primaryPanel = splitter.locator('.el-splitter-panel').first()
          const beforeWidth = (await primaryPanel.boundingBox())?.width ?? 0
          const handle = await splitter.locator('.el-splitter-bar').first().boundingBox()
          expect(handle).not.toBeNull()
          await page.mouse.move(handle!.x + handle!.width / 2, handle!.y + handle!.height / 2)
          await page.mouse.down()
          await page.mouse.move(handle!.x + handle!.width / 2 + 48, handle!.y + handle!.height / 2)
          await page.mouse.up()
          await expect
            .poll(async () => (await primaryPanel.boundingBox())?.width ?? 0)
            .toBeGreaterThan(beforeWidth + 20)
        }
      }
    } else {
      await expect(
        page.locator('.business-workspace-header:visible').getByText('专注模式', { exact: true })
      ).toBeVisible()
      if (path === 'batch') {
        await page.getByRole('switch', { name: '显示表格右侧工具栏' }).locator('..').click()
        await expect(page.getByRole('button', { name: '进入专注模式' })).toHaveCount(0)
      }
      await page.getByRole('switch', { name: '进入专注模式' }).locator('..').click()
      await expect(page.getByRole('heading', { name: title, exact: true })).toBeHidden()
      if (path === 'batch') {
        await expect(page.getByRole('button', { name: '退出专注模式' })).toBeVisible()
      }
      await page.screenshot({ path: join(visualDir, `mdm-${path}-focus.png`), fullPage: true })
      await page.keyboard.press('Escape')
      await expect(page.getByRole('heading', { name: title, exact: true })).toBeVisible()
    }
    if (path === 'warehouse-definition') {
      await page.getByRole('button', { name: '新增仓库', exact: true }).click()
      const dialog = page.locator('.el-dialog:visible')
      await expect(dialog.getByText('一位一品', { exact: true })).toHaveCount(0)
      const zoneSwitch = dialog
        .locator('.el-form-item')
        .filter({ hasText: '启用库区' })
        .locator('.el-switch')
      const binSwitch = dialog
        .locator('.el-form-item')
        .filter({ hasText: '启用库位' })
        .locator('.el-switch')
      await expect(zoneSwitch).not.toHaveClass(/is-checked/)
      await expect(binSwitch).not.toHaveClass(/is-checked/)
      await dialog
        .locator('.el-form-item')
        .filter({ hasText: '启用库位' })
        .locator('.el-switch')
        .click({ timeout: 15_000 })
      await expect(zoneSwitch).not.toHaveClass(/is-checked/)
      const singleSkuField = dialog.locator('.el-form-item').filter({ hasText: '一位一品' })
      await expect(singleSkuField.locator('.el-select')).toContainText('否')
      await page.screenshot({ path: join(visualDir, 'mdm-warehouse-dialog.png'), fullPage: true })
      await singleSkuField.locator('.el-select').click({ timeout: 15_000 })
      await page.getByRole('option', { name: '是' }).click({ timeout: 15_000 })
      await expect(singleSkuField.locator('.el-select')).toContainText('是')
    }
    if (path === 'serial') {
      await expect(page.getByText('采购', { exact: true }).first()).toBeVisible()
      await expect(page.getByText('原材料', { exact: true }).first()).toBeVisible()
      await page.getByRole('button', { name: '编辑', exact: true }).click()
      const dialog = page.locator('.el-dialog:visible')
      await expect(dialog.locator('.el-form-item').filter({ hasText: '工单' })).toContainText(
        'DEMO-WMS-001'
      )
      await expect(dialog.getByText('39b66f7c-3b4c-4b7d-b849-5ee7cb1d558a')).toHaveCount(0)
      await expect(dialog.locator('.el-form-item').filter({ hasText: '库位' })).toContainText(
        'RAW-A-BOARD-01'
      )
      await page.screenshot({
        path: join(visualDir, 'mdm-serial-dialog.png'),
        fullPage: true,
        animations: 'disabled'
      })
      await dialog.getByRole('button', { name: '取消' }).click()
    }
    if (path === 'batch') {
      await page.getByRole('button', { name: '呆滞口径' }).click()
      const policyDialog = page.locator('.el-dialog:visible')
      await expect(policyDialog.getByRole('switch')).toHaveAttribute('aria-checked', 'true')
      await policyDialog.getByRole('button', { name: '取消' }).click()
    }
    if (path === 'reservation') {
      await page.getByRole('button', { name: '新增预留' }).click()
      const dialog = page.locator('.el-dialog:visible')
      await dialog.getByRole('combobox', { name: '工单' }).click()
      await expect(page.getByRole('option', { name: '可领料测试工单' })).toBeVisible()
      await expect(page.getByRole('option', { name: '仅成品仓测试工单' })).toHaveCount(0)
      await page.screenshot({ path: join(visualDir, 'mdm-reservation-allowed-orders.png') })
      await dialog.getByRole('button', { name: '取消' }).click()
    }
    if (path === 'bin') {
      for (const [label, token] of [
        ['可存', '--el-color-success'],
        ['有库存', '--el-color-primary'],
        ['异常', '--el-color-danger'],
        ['停用', '--el-color-info']
      ] as const) {
        const swatch = page.locator('.el-checkbox-group .el-checkbox').filter({ hasText: label })
        const colors = await swatch.evaluate((element, colorToken) => {
          const reference = document.createElement('span')
          reference.style.color = `var(${colorToken})`
          element.appendChild(reference)
          const colors = {
            actual: getComputedStyle(element.querySelector('.el-checkbox__inner')!).backgroundColor,
            expected: getComputedStyle(reference).color
          }
          reference.remove()
          return colors
        }, token)
        expect(colors.actual, `${label} 筛选色应与库位状态色一致`).toBe(colors.expected)
      }
      const originalAppearance = await page.evaluate(() => ({
        dark: document.documentElement.classList.contains('dark'),
        boxMode: document.documentElement.getAttribute('data-box-mode')
      }))
      await page.evaluate(() => {
        document.documentElement.classList.add('dark')
        document.documentElement.setAttribute('data-box-mode', 'border-mode')
      })
      await page.screenshot({
        path: join(visualDir, 'mdm-bin-dark-border.png'),
        fullPage: true,
        animations: 'disabled'
      })
      await page.evaluate(() => {
        document.documentElement.setAttribute('data-box-mode', 'shadow-mode')
      })
      await page.screenshot({
        path: join(visualDir, 'mdm-bin-dark-shadow.png'),
        fullPage: true,
        animations: 'disabled'
      })
      await page.evaluate(({ dark, boxMode }) => {
        document.documentElement.classList.toggle('dark', dark)
        if (boxMode) document.documentElement.setAttribute('data-box-mode', boxMode)
        else document.documentElement.removeAttribute('data-box-mode')
      }, originalAppearance)
      await expect(page.locator('.rack-facade')).toBeVisible()
      await expect(page.locator('.rack-facade')).toHaveCSS('border-top-width', '12px')
      await expect(page.locator('.rack-level')).toHaveCount(2)
      const rackMore = page.getByRole('button', { name: '操作货架 1-1', exact: true })
      await expect(rackMore.locator('svg')).toBeVisible()
      const rackTile = page.getByRole('button', { name: /^货架 1-1，/ })
      const rackActions = page
        .locator('.rack-cell')
        .filter({ has: rackMore })
        .locator('.storage-card-actions')
      if ((page.viewportSize()?.width ?? 0) > 1200) {
        await expect(rackActions).toHaveCSS('opacity', '0')
      }
      await rackTile.hover()
      await expect(rackActions).toHaveCSS('opacity', '1')
      const rackTileBounds = await rackTile.boundingBox()
      const rackMoreBounds = await rackMore.boundingBox()
      expect(rackTileBounds).not.toBeNull()
      expect(rackMoreBounds).not.toBeNull()
      expect(rackMoreBounds!.x).toBeGreaterThan(rackTileBounds!.x + rackTileBounds!.width / 2)
      expect(rackMoreBounds!.y + rackMoreBounds!.height).toBeLessThanOrEqual(
        rackTileBounds!.y + rackTileBounds!.height
      )
      await expect(page.getByText('子单元 1', { exact: true })).toBeVisible()
      await expect(page.getByRole('button', { name: /^货架 1-1 子单元，/ })).toBeVisible()
      await rackMore.click()
      await expect(page.getByRole('menuitem', { name: '新增子单元' })).toBeVisible()
      await expect(page.getByRole('menuitem', { name: '删除库位' })).toBeVisible()
      await page.screenshot({
        path: join(visualDir, 'mdm-bin-more-actions.png'),
        animations: 'disabled'
      })
      await page.getByRole('menuitem', { name: '编辑库位' }).click()
      const editDialog = page.locator('.el-dialog:visible')
      await editDialog
        .locator('.el-form-item')
        .filter({ hasText: '上级存储单元' })
        .locator('.el-select')
        .click()
      await expect(page.getByRole('option', { name: /RAW-A-BOARD-01/ })).toBeVisible()
      await expect(page.getByRole('option', { name: /RAW-A-SH-1-1-A/ })).toHaveCount(0)
      await editDialog.getByRole('button', { name: '取消' }).click()
      const tile = page.getByRole('button', { name: /^一号垛位，/ })
      const blockMore = page.getByRole('button', { name: '操作一号垛位', exact: true })
      const blockActions = page
        .locator('.bin-node__tile')
        .filter({ has: blockMore })
        .locator('.storage-card-actions')
      if ((page.viewportSize()?.width ?? 0) > 1200) {
        await expect(blockActions).toHaveCSS('opacity', '0')
      }
      await tile.hover()
      await expect(blockActions).toHaveCSS('opacity', '1')
      const blockTileBounds = await tile.boundingBox()
      const blockMoreBounds = await blockMore.boundingBox()
      expect(blockTileBounds).not.toBeNull()
      expect(blockMoreBounds).not.toBeNull()
      expect(blockMoreBounds!.x).toBeGreaterThan(blockTileBounds!.x + blockTileBounds!.width / 2)
      expect(blockMoreBounds!.y + blockMoreBounds!.height).toBeLessThanOrEqual(
        blockTileBounds!.y + blockTileBounds!.height
      )
      await blockMore.click()
      await expect(page.getByRole('menuitem', { name: '编辑库位' })).toBeVisible()
      await page.screenshot({
        path: join(visualDir, 'mdm-bin-block-more-actions.png'),
        animations: 'disabled'
      })
      await page.keyboard.press('Escape')
      await tile.hover()
      await expect(page.getByText(/库存金额.*960/)).toBeVisible()
      await expect(page.getByText(/呆滞物料 1 种/)).toBeVisible()
      await tile.dblclick()
      await expect(page.getByText('B-20260924-01', { exact: true })).toBeVisible()
      await page.getByRole('button', { name: '关闭', exact: true }).click()
      await tile.click()
      await expect(page.getByText('一号垛位 · 快捷业务')).toBeVisible()
      await expect(page.getByRole('button', { name: '采购入库' })).toBeVisible()
      await page.screenshot({
        path: join(visualDir, 'mdm-bin-action-dialog.png'),
        fullPage: true,
        animations: 'disabled'
      })
      await page.getByRole('button', { name: '生产入库' }).click()
      await expect(page).toHaveURL(/\/wms\/receipt-issue\/stock-operation/)
    }
  }
  expect(errors).toEqual([])
})

test('生产工单类型显示可配置的领料仓库范围', async ({ page }, testInfo) => {
  test.setTimeout(180_000)
  await installFixtures(page)
  const root = {
    id: 'wms-document-root',
    parentId: null,
    name: 'MdmMasterData',
    path: '/mdm',
    component: '/index/index',
    type: 'folder',
    sort: 1,
    meta: meta('MDM主数据')
  }
  const folder = {
    id: 'wms-operational-root',
    parentId: root.id,
    name: 'MdmOperationalMaster',
    path: 'operational-master',
    component: '',
    type: 'folder',
    sort: 1,
    meta: meta('运营主数据')
  }
  const menu = {
    id: 'wms-document-menu',
    parentId: folder.id,
    name: 'MdmDocumentType',
    path: 'document-type',
    component: '/mdm/document-type',
    type: 'menu',
    sort: 1,
    meta: meta('单据类型')
  }
  const buttons = ['View', 'Add', 'Copy', 'Edit', 'Delete', 'Export'].map((action) => ({
    id: `wms-document-${action}`,
    parentId: menu.id,
    name: `MdmDocumentType:${action}`,
    path: '',
    component: '',
    type: 'button',
    sort: 1,
    meta: meta(action),
    children: []
  }))
  const tree = {
    ...root,
    children: [{ ...folder, children: [{ ...menu, children: buttons }] }]
  }
  const flat = [root, folder, menu, ...buttons]
  await page.route('**/rest/v1/rpc/get_menus_for_current_application', (route) =>
    route.fulfill({ json: { flat, tree: [tree] } })
  )
  await page.route('**/rest/v1/sys_menu?*', (route) =>
    route.fulfill({
      json: [
        {
          id: 'wms-work-order-menu',
          parent_id: null,
          name: 'MesWorkOrder',
          path: 'work-order',
          component: '/mes/manufacturing',
          type: 'menu',
          app_code: 'mes',
          sort: 1,
          meta: meta('生产工单')
        }
      ]
    })
  )
  await page.route('**/rest/v1/mdm_document_type?*', (route) =>
    route.fulfill({
      status: 206,
      headers: { 'content-range': '0-0/1' },
      json: [
        {
          id: 'wms-type-id',
          tenant_id: tenantId,
          menu_id: 'wms-work-order-menu',
          document_type_code: 'PP13',
          document_type_name: '演示成品装配',
          is_default: false,
          remark: '',
          sort_order: 10,
          text_color: '',
          tag_style: 'primary',
          enabled: true,
          extension_fields: [],
          allowed_issue_warehouse_types: ['raw_material'],
          tenant: { tenant_code: 'DEMO', tenant_name: '示例工厂' }
        }
      ]
    })
  )
  await page.goto('/#/mdm/operational-master/document-type', {
    waitUntil: 'domcontentloaded'
  })
  await expect(page.getByRole('heading', { name: '单据类型', exact: true })).toBeVisible({
    timeout: 120_000
  })
  await expect(page.getByText('演示成品装配', { exact: true }).first()).toBeVisible()
  await page.getByRole('button', { name: '编辑', exact: true }).click()
  const dialog = page.locator('.el-dialog:visible')
  const field = dialog.locator('.el-form-item').filter({ hasText: '允许领料的仓库类型' })
  await expect(field).toBeVisible()
  await expect(field).toContainText('原料仓')
  await field.scrollIntoViewIfNeeded()
  const visualDir = join(process.cwd(), '.artifacts', 'wms-visual', testInfo.project.name)
  mkdirSync(visualDir, { recursive: true })
  await page.screenshot({ path: join(visualDir, 'mdm-work-order-type-policy.png'), fullPage: true })
  await field.locator('.el-select').click()
  await page.getByRole('option', { name: '成品仓' }).click()
  await expect(field).toContainText('成品仓')
  await page.screenshot({
    path: join(visualDir, 'mdm-work-order-type-policy-selected.png'),
    fullPage: true
  })
  const saveRequest = page.waitForRequest(
    (request) => request.method() === 'PATCH' && request.url().includes('/mdm_document_type?')
  )
  await dialog.getByRole('button', { name: '保存更改' }).click()
  const payload = (await saveRequest).postDataJSON() as {
    allowed_issue_warehouse_types: string[]
  }
  expect(payload.allowed_issue_warehouse_types).toEqual(['raw_material', 'finished'])
})

test('库区新增弹窗先出现，再等待基础数据', async ({ page }) => {
  await installFixtures(page)
  await page.goto('/#/mdm/inventory-master/zone', { waitUntil: 'domcontentloaded' })
  await expect(page.getByRole('heading', { name: '库区管理', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: '新增库区' })).toBeEnabled()

  let releaseCategories!: () => void
  const categoryGate = new Promise<void>((resolve) => {
    releaseCategories = resolve
  })
  await page.route('**/rest/v1/mdm_material_category*', async (route) => {
    await categoryGate
    await route.fulfill({ json: [] })
  })

  try {
    await page.getByRole('button', { name: '新增库区' }).click()
    const dialog = page.locator('.el-dialog:visible').filter({ hasText: '新增库区' })
    await expect(dialog).toBeVisible()
    await expect(dialog.locator('.art-overlay-loading.is-loading')).toBeVisible()
  } finally {
    releaseCategories()
  }
  await expect(page.locator('.el-dialog:visible .art-overlay-loading.is-loading')).toHaveCount(0)
})

test('库区和库位筛选无结果时保留筛选与重置入口', async ({ page }) => {
  await installFixtures(page)
  await page.goto('/#/mdm/inventory-master/zone', { waitUntil: 'domcontentloaded' })
  await expect(page.getByRole('heading', { name: '库区管理', exact: true })).toBeVisible()
  const zoneCard = page.locator('.zone-tile').first()
  const zoneMore = zoneCard.getByRole('button', { name: /^操作/ })
  if ((page.viewportSize()?.width ?? 0) > 1200) {
    await expect(zoneCard.locator('.storage-card-actions')).toHaveCSS('opacity', '0')
  }
  await zoneCard.locator('.storage-tile').hover()
  await expect(zoneCard.locator('.storage-card-actions')).toHaveCSS('opacity', '1')
  await zoneMore.click()
  await expect(page.getByRole('menuitem', { name: '编辑库区' })).toBeVisible()
  await expect(page.getByRole('menuitem', { name: '删除库区' })).toBeVisible()
  await page.keyboard.press('Escape')

  const zoneFilters = page.locator('.el-checkbox-group:visible').last()
  await expect(zoneFilters.locator('.el-checkbox')).toHaveCount(4)
  for (const label of ['可存', '有库存', '异常', '停用']) {
    await zoneFilters.getByText(label, { exact: true }).click()
  }
  await expect(page.getByText('暂无匹配库区', { exact: true })).toBeVisible()
  await expect(page.locator('.el-checkbox-group .el-checkbox')).toHaveCount(4)
  await page.getByRole('button', { name: '重置筛选' }).first().click()
  await expect(page.locator('.zone-tile').first()).toBeVisible()

  await page.goto('/#/mdm/inventory-master/bin', { waitUntil: 'domcontentloaded' })
  await expect(page.getByRole('heading', { name: '库位管理', exact: true })).toBeVisible()
  const binFilters = page.locator('.el-checkbox-group:visible').last()
  await expect(binFilters.locator('.el-checkbox')).toHaveCount(4)
  for (const label of ['可存', '有库存', '异常', '停用']) {
    await binFilters.getByText(label, { exact: true }).click()
  }
  await expect(page.getByText('暂无匹配库位', { exact: true })).toBeVisible()
  await expect(page.locator('.el-checkbox-group .el-checkbox')).toHaveCount(4)
  await page.getByRole('button', { name: '重置筛选' }).first().click()
  await expect(page.locator('.rack-facade')).toBeVisible()
})

test('新增库区时可选分类为空会提交 null', async ({ page }) => {
  await installFixtures(page)
  await page.route('**/rest/v1/mdm_material_category*', (route) =>
    route.fulfill({
      json: [{ id: materialId, category_code: 'BOARD', category_name: '板材', status: 'enabled' }]
    })
  )
  let submitted: Record<string, unknown> | undefined
  await page.route('**/rest/v1/mdm_warehouse_zone?*', async (route) => {
    if (route.request().method() !== 'POST') return route.fallback()
    submitted = route.request().postDataJSON() as Record<string, unknown>
    await route.fulfill({ status: 201, json: [{ id: zoneId }] })
  })
  await page.goto('/#/mdm/inventory-master/zone', { waitUntil: 'domcontentloaded' })
  await page.getByRole('button', { name: '新增库区' }).click()
  const dialog = page.locator('.el-dialog:visible').filter({ hasText: '新增库区' })
  await expect(dialog.locator('.art-overlay-loading.is-loading')).toHaveCount(0)
  await dialog
    .locator('.el-form-item')
    .filter({ hasText: '库区编码' })
    .locator('input')
    .fill('C100201')
  await dialog
    .locator('.el-form-item')
    .filter({ hasText: '库区名称' })
    .locator('input')
    .fill('货架区')
  const categoryField = dialog.locator('.el-form-item').filter({ hasText: '存放物料分类' })
  await categoryField.locator('.el-select').click()
  await page.getByRole('option', { name: '板材 · BOARD' }).click()
  await categoryField.locator('.el-select').hover()
  await categoryField.locator('.el-select__clear').click()
  await dialog.getByRole('button', { name: '确定' }).click()
  await expect
    .poll(() => submitted)
    .toMatchObject({
      zone_code: 'C100201',
      zone_name: '货架区',
      category_id: null,
      purpose: null
    })
  await expect(dialog).toBeHidden()
})
