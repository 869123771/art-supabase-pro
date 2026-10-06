import { expect, test } from '@playwright/test'
import { installFixtures, meta, tenantId } from './support/inventory-fixtures'
import { mockApplicationMenus } from './support/menu-rpc'

for (const serialManaged of [false, true]) {
  test(`${serialManaged ? 'SN' : '板材'}原发货退货空白单号拦截与失败重试`, async ({
    page
  }, testInfo) => {
    test.setTimeout(90_000)
    await installFixtures(page)
    await page.route('**/rpc/get_accessible_applications', (route) =>
      route.fulfill({
        json: [
          { code: 'platform', name: '测试平台', baseUrl: '/' },
          { code: 'wms', name: 'WMS', baseUrl: '/wms/' }
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
      meta: meta('WMS')
    }
    const menu = {
      id: 'return-menu',
      parentId: root.id,
      name: 'WmsSalesReturn',
      path: 'receipt-issue/sales-return',
      component: '/wms/receipt-issue/sales-return',
      type: 'menu',
      sort: 1,
      meta: meta('销售退货入库')
    }
    await mockApplicationMenus(page, {
      wms: [
        root,
        menu,
        ...['View', 'Add'].map((action) => ({
          id: `return-${action}`,
          parentId: menu.id,
          name: `WmsSalesReturn:${action}`,
          path: '',
          component: '',
          type: 'button',
          sort: 1,
          meta: meta(action)
        }))
      ]
    })
    await page.route('**/rest/v1/wms_sales_outbound_allocation?*', (route) =>
      route.fulfill({
        json: [
          {
            id: 'allocation-test',
            tenant_id: tenantId,
            quantity: 10,
            created_at: '2026-10-01T01:02:03Z',
            serial_ids: serialManaged ? ['return-sn-1', 'return-sn-2', 'returned-sn'] : [],
            returns: serialManaged ? [{ quantity: 1, serial_ids: ['returned-sn'] }] : [],
            shippingNotice: { document_no: 'SHIP-RETURN-001', project_id: null },
            batch: {
              batch_no: 'RETURN-BATCH-001',
              project_id: null,
              material: { material_name: '测试退货板材' }
            }
          }
        ],
        headers: { 'content-range': '0-0/1', 'access-control-expose-headers': 'content-range' }
      })
    )
    await page.route('**/rest/v1/mdm_warehouse?*', (route) =>
      route.fulfill({
        json: [
          {
            id: 'return-warehouse',
            tenant_id: tenantId,
            warehouse_code: 'RETURN-WH',
            warehouse_name: '测试退货仓库',
            status: 'enabled',
            enable_locations: false
          }
        ]
      })
    )
    const payloads: unknown[] = []
    let serialFailed = true
    if (serialManaged) {
      await page.route('**/rest/v1/wms_serial_number?*', (route) =>
        serialFailed
          ? route.fulfill({ status: 503, json: { message: 'SN 测试加载失败' } })
          : route.fulfill({
              json: [
                { id: 'return-sn-1', serial_no: 'RETURN-SN-001', status: 'out' },
                { id: 'return-sn-2', serial_no: 'RETURN-SN-002', status: 'out' },
                { id: 'returned-sn', serial_no: 'RETURN-SN-OLD', status: 'out' }
              ]
            })
      )
    }
    let failed = true
    await page.route('**/rpc/wms_receive_sales_return_secure', (route) => {
      payloads.push(route.request().postDataJSON())
      return failed
        ? route.fulfill({ status: 400, json: { code: 'P0001', message: '测试退货入库失败' } })
        : route.fulfill({ json: null })
    })
    await page.goto('#/wms/receipt-issue/sales-return')
    await page.getByRole('textbox', { name: '按发货通知单号选择', exact: true }).click()
    const picker = page.getByRole('dialog', { name: '选择原销售出库', exact: true })
    await expect(picker.getByText('2026-10-01 09:02:03', { exact: true })).toBeVisible()
    await expect(picker.getByText('2026-10-01T01:02:03Z', { exact: true })).toHaveCount(0)
    if (testInfo.project.name === 'mobile-390') {
      await picker.locator('.el-table__body-wrapper .el-scrollbar__wrap').evaluate((element) => {
        element.scrollLeft = element.scrollWidth
      })
      await expect(picker.getByText('2026-10-01 09:02:03', { exact: true })).toBeInViewport()
    }
    await page.screenshot({
      path: testInfo.outputPath('return-allocation-picker.png'),
      animations: 'disabled'
    })
    if (testInfo.project.name === 'mobile-390') {
      await picker.locator('.el-table__body-wrapper .el-scrollbar__wrap').evaluate((element) => {
        element.scrollLeft = 0
      })
    }
    await picker
      .locator('.el-table__body')
      .getByText('SHIP-RETURN-001 · 测试退货板材 · RETURN-BATCH-001', { exact: true })
      .click()
    await picker.getByRole('button', { name: '确定', exact: true }).click()
    await page.getByRole('combobox', { name: /退货入库仓库/ }).click()
    await page.getByRole('option', { name: '测试退货仓库 · RETURN-WH', exact: true }).click()
    const reference = page.getByRole('textbox', { name: /退货单号/ })
    if (serialManaged) {
      await expect(page.getByRole('button', { name: '确认退货入库', exact: true })).toBeDisabled()
      await reference.fill('RETURN-001')
      await expect(page.getByRole('button', { name: '重新加载 SN', exact: true })).toBeVisible()
      await page.screenshot({
        path: testInfo.outputPath('return-sn-load-error.png'),
        animations: 'disabled'
      })
      serialFailed = false
      await page.getByRole('button', { name: '重新加载 SN', exact: true }).click()
      await expect(reference).toHaveValue('RETURN-001')
      const scan = page.getByRole('textbox', { name: 'PDA 扫描退回 SN', exact: true })
      await scan.fill('RETURN-SN-OLD')
      await scan.press('Enter')
      await expect(page.getByText('原发货记录中未找到可退的该 SN', { exact: true })).toBeVisible()
      await scan.fill('RETURN-SN-001')
      await scan.press('Enter')
      await scan.fill('RETURN-SN-001')
      await scan.press('Enter')
      await expect(page.getByText('该 SN 已选择', { exact: true })).toBeVisible()
      await scan.fill('RETURN-SN-002')
      await scan.press('Enter')
      await expect(page.getByRole('spinbutton', { name: /本次退货数量/ })).toBeDisabled()
    }
    await reference.fill('   ')
    await page.getByRole('button', { name: '确认退货入库', exact: true }).click()
    await expect(page.getByText('请填写退货单号', { exact: true })).toBeVisible()
    expect(payloads).toHaveLength(0)
    await reference.fill('RETURN-001')
    if (!serialManaged) await page.getByRole('spinbutton', { name: /本次退货数量/ }).fill('2')
    await reference.click()
    await page.getByRole('button', { name: '确认退货入库', exact: true }).click()
    await expect(page.getByText('测试退货入库失败', { exact: false }).first()).toBeVisible()
    await expect(reference).toHaveValue('RETURN-001')
    await expect(
      page.getByRole('textbox', { name: '按发货通知单号选择', exact: true })
    ).toHaveValue('SHIP-RETURN-001 · 测试退货板材 · RETURN-BATCH-001')
    await expect(
      page
        .getByRole('combobox', { name: /退货入库仓库/ })
        .locator('xpath=ancestor::div[contains(@class, "el-select__wrapper")][1]')
    ).toContainText('测试退货仓库 · RETURN-WH')
    await expect(page.getByRole('spinbutton', { name: /本次退货数量/ })).toHaveAttribute(
      'aria-valuenow',
      '2'
    )
    await page.screenshot({
      path: testInfo.outputPath('return-save-rejected.png'),
      animations: 'disabled'
    })
    failed = false
    await page.getByRole('button', { name: '确认退货入库', exact: true }).click()
    await expect(reference).toHaveValue('')
    expect(payloads).toHaveLength(2)
    expect(payloads[0]).toEqual(payloads[1])
    expect(payloads[1]).toMatchObject({
      p_payload: {
        outbound_allocation_id: 'allocation-test',
        warehouse_id: 'return-warehouse',
        quantity: 2,
        reference_no: 'RETURN-001'
      }
    })
    if (serialManaged)
      expect(payloads[1]).toMatchObject({
        p_payload: { serial_ids: ['return-sn-1', 'return-sn-2'] }
      })
  })
}
