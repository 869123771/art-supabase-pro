import { expect, test, type Page } from '@playwright/test'

const tenantId = '00000000-0000-4000-8000-000000000001'
const departmentId = '00000000-0000-4000-8000-000000000101'

async function installFixtures(page: Page) {
  const meta = (title: string, icon: string) => ({
    title,
    icon,
    roles: ['R_SUPER'],
    is_hide: false,
    is_enable: true,
    keep_alive: true
  })
  const root = {
    id: 'visual-equipment-mdm-root',
    parentId: null,
    name: 'MdmRoot',
    path: '/mdm',
    component: '/index/index',
    type: 'folder',
    sort: 1,
    meta: meta('MDM主数据', 'ri:database-2-line')
  }
  const equipment = {
    id: 'visual-production-equipment',
    parentId: root.id,
    name: 'MdmProductionEquipment',
    path: 'equipment/production',
    component: '/mdm/equipment/production',
    type: 'menu',
    sort: 1,
    meta: meta('生产设备', 'ri:tools-line')
  }
  const buttons = [
    'View',
    'Add',
    'Copy',
    'Edit',
    'Delete',
    'Import',
    'Export',
    'Enable',
    'Disable'
  ].map((action, index) => ({
    id: `visual-production-equipment-${action}`,
    parentId: equipment.id,
    name: `MdmProductionEquipment:${action}`,
    path: '',
    component: '',
    type: 'button',
    sort: index + 1,
    meta: meta(action, '')
  }))

  await page.route('**/rest/v1/rpc/current_is_super', (route) => route.fulfill({ json: true }))
  await page.route('**/rest/v1/rpc/get_accessible_applications', (route) =>
    route.fulfill({ json: [{ code: 'platform', name: '测试平台', baseUrl: '/' }] })
  )
  await page.route('**/rest/v1/rpc/get_menus_for_current_application', (route) =>
    route.fulfill({
      json: {
        flat: [root, equipment, ...buttons],
        tree: [{ ...root, children: [{ ...equipment, children: [] }] }]
      }
    })
  )
  await page.route('**/rest/v1/rpc/mdm_list_production_equipment_secure', (route) =>
    route.fulfill({
      json: {
        records: [
          {
            id: '00000000-0000-4000-8000-000000000501',
            tenant_id: tenantId,
            tenant_name: '华东制造',
            equipment_code: 'EQ-ASSY-001',
            equipment_name: '总装一线拧紧机',
            category_id: '00000000-0000-4000-8000-000000000201',
            category_name: '装配设备',
            production_department_id: departmentId,
            department_name: '总装一线',
            location_id: '00000000-0000-4000-8000-000000000301',
            location_name: '一号厂房 A 区',
            work_center_id: '00000000-0000-4000-8000-000000000401',
            work_center_name: '总装工作中心',
            responsible_employee_id: null,
            responsible_name: '张明',
            supplier_id: null,
            supplier_name: '智造设备供应商',
            equipment_brand: 'Atlas',
            model: 'PF6000',
            manufacturer: 'Atlas Copco',
            factory_no: 'AC-2026-001',
            fixed_asset_no: 'FA-001',
            acceptance_date: '2026-08-20',
            enable_date: '2026-08-25',
            traffic_light_card_no: 'LIGHT-001',
            andon_box_no: 'ANDON-001',
            pulse_interval_seconds: 60,
            standard_utilization: 85,
            sync_work_center: true,
            operation_status: 'normal',
            status: 'enabled',
            sort: 10,
            create_time: '2026-08-20T08:00:00Z',
            update_time: '2026-09-05T09:30:00Z'
          }
        ],
        total: 1,
        overview: { total: 1, enabled: 1, connected: 1, unassigned: 0 },
        references: {
          categories: [
            {
              id: '00000000-0000-4000-8000-000000000201',
              tenant_id: tenantId,
              code: 'ASSEMBLY',
              name: '装配设备'
            }
          ],
          departments: [
            {
              id: departmentId,
              tenant_id: tenantId,
              parent_id: null,
              code: 'LINE-01',
              name: '总装一线',
              kind: 'line'
            }
          ],
          locations: [
            {
              id: '00000000-0000-4000-8000-000000000301',
              tenant_id: tenantId,
              parent_id: null,
              code: 'PLANT-A',
              name: '一号厂房 A 区'
            }
          ],
          work_centers: [
            {
              id: '00000000-0000-4000-8000-000000000401',
              tenant_id: tenantId,
              department_id: departmentId,
              code: 'WC-ASSY-01',
              name: '总装工作中心'
            }
          ],
          suppliers: []
        }
      }
    })
  )
}

test('production equipment master keeps the enterprise workspace and dialog visual system', async ({
  page
}, testInfo) => {
  test.setTimeout(120_000)
  await installFixtures(page)
  const pageErrors: string[] = []
  page.on('pageerror', (error) => pageErrors.push(error.message))

  await page.goto('/#/mdm/equipment/production', { waitUntil: 'domcontentloaded' })
  await expect(page.getByRole('heading', { name: '生产设备', exact: true })).toBeVisible({
    timeout: 60_000
  })
  await expect(page.getByText('总装一线拧紧机', { exact: true })).toBeVisible()
  await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 60_000 })
  const guide = page.getByRole('button', { name: '知道了', exact: true })
  if (await guide.isVisible()) await guide.click()
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)
  ).toBe(true)
  await page.screenshot({
    path: testInfo.outputPath('production-equipment.png'),
    animations: 'disabled'
  })

  await page.getByRole('button', { name: '新增设备', exact: true }).click()
  const dialog = page.getByRole('dialog')
  await expect(dialog.getByText('PRODUCTION EQUIPMENT', { exact: true })).toBeVisible()
  await expect(dialog.getByRole('tab', { name: '生产归属', exact: true })).toBeVisible()
  await expect(dialog.getByRole('tab', { name: '设备接入', exact: true })).toBeVisible()
  await dialog.getByRole('tab', { name: '生产归属', exact: true }).click()
  await expect(dialog.getByText('部门 / 产线', { exact: true })).toBeVisible()
  await page.screenshot({
    path: testInfo.outputPath('production-equipment-dialog.png'),
    animations: 'disabled'
  })

  expect(pageErrors).toEqual([])
})
