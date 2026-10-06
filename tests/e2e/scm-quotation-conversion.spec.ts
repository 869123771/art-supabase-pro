import { expect, test, type Route } from '@playwright/test'
import { prepareIsolatedSession } from './support/isolated-session'

test.use({ storageState: { cookies: [], origins: [] } })
test.setTimeout(120_000)
test.beforeEach(async ({ page }) => {
  await prepareIsolatedSession(page)
})
test('路由离开强制关闭后不接收旧转单成功事件', async ({ page }) => {
  let pending: Route | undefined
  await page.route('**/rest/v1/rpc/scm_convert_standard_quotation', (route) => {
    pending = route
  })
  await page.goto('/tests/e2e/fixtures/quotation-conversion.html')
  await page.getByRole('button', { name: '销售转单', exact: true }).click()
  const dialog = page.getByRole('dialog')
  await dialog.getByRole('button', { name: '生成目标单据', exact: true }).click()
  await expect.poll(() => Boolean(pending)).toBe(true)
  // Activate the fixture navigation command without testing a pointer click through the modal mask.
  await page
    .getByRole('button', { name: '离开报价页面', exact: true })
    .evaluate((element) => element.click())
  await expect(dialog).not.toBeVisible()
  const oldResponse = page.waitForResponse('**/rest/v1/rpc/scm_convert_standard_quotation')
  await pending!.fulfill({
    json: { id: 'target-a', document_no: 'ORDER-A', target_kind: 'sales_order', reused: false }
  })
  await oldResponse
  await page.evaluate(
    () =>
      new Promise<void>((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
      )
  )
  await expect(page.getByTestId('success-count')).toHaveText('0')
})
test('转单成功仅通知当前弹窗且旧提交不关闭新弹窗', async ({ page }) => {
  const pending: Route[] = []
  let hold = true
  const response = {
    id: 'target-a',
    document_no: 'ORDER-A',
    target_kind: 'sales_order',
    reused: false
  }
  await page.route('**/rest/v1/rpc/scm_convert_standard_quotation', (route) => {
    expect(route.request().postDataJSON()).toEqual({
      quotation_id: 'quote-a',
      target_kind: 'sales_order',
      supplier_id: null
    })
    if (hold) {
      pending.push(route)
      return
    }
    return route.fulfill({ json: response })
  })
  await page.goto('/tests/e2e/fixtures/quotation-conversion.html')
  await page.getByRole('button', { name: '销售转单', exact: true }).click()
  const dialog = page.getByRole('dialog')
  await dialog.getByRole('button', { name: '生成目标单据', exact: true }).click()
  await expect.poll(() => pending.length).toBe(1)
  await dialog.getByRole('button', { name: 'Close this dialog', exact: true }).click()
  await expect(dialog).not.toBeVisible()
  await page.getByRole('button', { name: '销售转单', exact: true }).click()
  await expect(dialog).toBeVisible()
  const oldResponse = page.waitForResponse('**/rest/v1/rpc/scm_convert_standard_quotation')
  await pending[0].fulfill({ json: response })
  await oldResponse
  await page.evaluate(
    () =>
      new Promise<void>((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
      )
  )
  await expect(page.getByTestId('success-count')).toHaveText('0')
  await expect(dialog).toBeVisible()
  hold = false
  await dialog.getByRole('button', { name: '生成目标单据', exact: true }).click()
  await expect(page.getByTestId('success-count')).toHaveText('1')
  await expect(dialog).not.toBeVisible()
})
test('物料编码引用重试后恢复默认配置', async ({ page }, testInfo) => {
  let fail = true
  await page.route('**/rest/v1/sys_dictionary?**', (route) =>
    route.fulfill({ json: [{ id: 'source-a', label: '自制', value: 'self_made', sort: 1 }] })
  )
  const references: Record<string, Record<string, string>[]> = {
    mdm_material_category: [
      { id: 'category-a', tenant_id: 'tenant-a', category_code: 'CAT', category_name: '配件' }
    ],
    mdm_material_type: [
      { id: 'type-a', tenant_id: 'tenant-a', type_code: 'TYPE', type_name: '半成品' }
    ],
    mdm_unit_of_measure: [
      { id: 'unit-a', tenant_id: 'tenant-a', unit_code: 'UNIT', unit_name: '件' }
    ],
    mdm_material_code_rule: [
      { id: 'rule-a', tenant_id: 'tenant-a', rule_code: 'RULE', rule_name: '半成品编码' }
    ]
  }
  for (const [table, rows] of Object.entries(references))
    await page.route(`**/rest/v1/${table}?**`, (route) => {
      expect(new URL(route.request().url()).searchParams.get('tenant_id')).toBe('eq.tenant-a')
      return fail && table === 'mdm_material_type'
        ? route.fulfill({
            status: 500,
            json: { code: 'XX000', message: 'technical reference failure' }
          })
        : route.fulfill({ json: rows })
    })
  await page.goto('/tests/e2e/fixtures/quotation-conversion.html')
  await page.getByRole('button', { name: '物料编码', exact: true }).click()
  const dialog = page.getByRole('dialog')
  await expect(dialog.getByText('物料主数据加载失败，请重试', { exact: true })).toBeVisible()
  await expect(dialog.getByText('待编码物料', { exact: true })).toBeVisible()
  fail = false
  await dialog.getByRole('button', { name: '重新加载', exact: true }).click()
  for (const label of ['半成品', '配件 · CAT', '件', '半成品编码'])
    await expect(dialog.getByText(label, { exact: true })).toBeVisible()
  await page.screenshot({
    path: testInfo.outputPath('material-recovered.png'),
    animations: 'disabled'
  })
})

test('工单类型失败重试后保留报价明细并恢复默认类型', async ({ page }, testInfo) => {
  let fail = true
  await page.route('**/rest/v1/sys_menu?**', (route) =>
    route.fulfill({ json: { id: 'work-menu' } })
  )
  await page.route('**/rest/v1/mdm_document_type?**', (route) => {
    expect(new URL(route.request().url()).searchParams.get('tenant_id')).toBe('eq.tenant-a')
    return fail
      ? route.fulfill({ status: 500, json: { code: 'XX000', message: 'technical type failure' } })
      : route.fulfill({
          json: [
            {
              id: 'work-type',
              tenant_id: 'tenant-a',
              document_type_name: '标准生产工单',
              document_type_code: 'WO',
              is_default: true
            }
          ]
        })
  })
  await page.goto('/tests/e2e/fixtures/quotation-conversion.html')
  await page.getByRole('button', { name: '生产工单', exact: true }).click()
  const dialog = page.getByRole('dialog')
  await expect(dialog.getByText('工单类型加载失败，请重试', { exact: true })).toBeVisible()
  await expect(dialog.getByText('工单组件', { exact: true })).toBeVisible()
  fail = false
  await dialog.getByRole('button', { name: '重新加载', exact: true }).click()
  await expect(dialog.getByText('标准生产工单', { exact: true })).toBeVisible()
  await page.screenshot({
    path: testInfo.outputPath('work-order-recovered.png'),
    animations: 'disabled'
  })
})
test('报价 BOM 引用失败保留明细且可原地重试', async ({ page }, testInfo) => {
  let fail = true
  let holdSubmit = true
  let pendingSubmit: Route | undefined
  const bomResult = { id: 'bom-a', bom_code: 'BOM-A', reused: false }
  await page.route('**/rest/v1/rpc/scm_convert_quotation_to_bom', (route) => {
    expect(route.request().postDataJSON()).toEqual({
      p_quotation_id: 'quote-a',
      p_parent_material_id: 'parent-a'
    })
    if (holdSubmit) {
      pendingSubmit = route
      return
    }
    return route.fulfill({ json: bomResult })
  })
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error.message))
  await page.route('**/rest/v1/mdm_material?**', (route) => {
    expect(new URL(route.request().url()).searchParams.get('tenant_id')).toBe('eq.tenant-a')
    return fail
      ? route.fulfill({
          status: 500,
          json: { code: 'XX000', message: 'technical material failure' }
        })
      : route.fulfill({
          json: [
            {
              id: 'parent-a',
              tenant_id: 'tenant-a',
              material_code: 'P1',
              material_name: '测试父件',
              description: '测试父件',
              base_unit_id: 'unit-a',
              baseUnitRecord: { unit_name: '件' }
            }
          ]
        })
  })
  await page.goto('/tests/e2e/fixtures/quotation-conversion.html')
  await page.getByRole('button', { name: '报价 BOM', exact: true }).click()
  const dialog = page.getByRole('dialog')
  await expect(dialog.getByText('父件物料加载失败，请重试', { exact: true })).toBeVisible()
  await expect(dialog.getByText('测试组件', { exact: true })).toBeVisible()
  await page.screenshot({
    path: testInfo.outputPath('bom-reference-error.png'),
    animations: 'disabled'
  })
  fail = false
  await dialog.getByRole('button', { name: '重新加载', exact: true }).click()
  await dialog.getByRole('combobox').click()
  await page.getByRole('option', { name: 'P1 · 测试父件', exact: true }).click()
  await expect(dialog.getByText('P1 · 测试父件', { exact: true })).toBeVisible()
  await page.screenshot({
    path: testInfo.outputPath('bom-reference-recovered.png'),
    animations: 'disabled'
  })
  await dialog.getByRole('button', { name: '执行生成', exact: true }).click()
  await expect.poll(() => Boolean(pendingSubmit)).toBe(true)
  await dialog.getByRole('button', { name: 'Close this dialog', exact: true }).click()
  await expect(dialog).not.toBeVisible()
  await page.getByRole('button', { name: '报价 BOM', exact: true }).click()
  await expect(dialog.getByRole('combobox')).toBeVisible()
  const oldResponse = page.waitForResponse('**/rest/v1/rpc/scm_convert_quotation_to_bom')
  await pendingSubmit!.fulfill({ json: bomResult })
  await oldResponse
  await page.evaluate(
    () =>
      new Promise<void>((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
      )
  )
  await expect(page.getByTestId('success-count')).toHaveText('0')
  await expect(dialog).toBeVisible()
  holdSubmit = false
  await dialog.getByRole('combobox').click()
  await page.getByRole('option', { name: 'P1 · 测试父件', exact: true }).click()
  await dialog.getByRole('button', { name: '执行生成', exact: true }).click()
  await expect(page.getByTestId('success-count')).toHaveText('1')
  await expect(dialog).not.toBeVisible()
  expect(errors).toEqual([])
})
test('报价转单供应商按需加载、重试与旧响应失效', async ({ page }, testInfo) => {
  let fail = true
  let hold = false
  let reads = 0
  const pending: Route[] = []
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error.message))
  await page.route('**/rest/v1/rpc/scm_purchase_suppliers_secure', (route) => {
    reads++
    if (hold) {
      hold = false
      pending.push(route)
      return
    }
    return fail
      ? route.fulfill({ status: 403, json: { code: '42501', message: 'permission denied' } })
      : route.fulfill({
          json: [{ id: 'supplier-a', supplier_name: '当前供应商', supplier_code: 'S1' }]
        })
  })
  await page.goto('/tests/e2e/fixtures/quotation-conversion.html')
  await page.getByRole('button', { name: '销售转单', exact: true }).click()
  const dialog = page.getByRole('dialog')
  await expect(
    dialog.getByText('生成销售订单草稿，继续维护交付与收款计划。', { exact: true })
  ).toBeVisible()
  expect(reads).toBe(0)
  await dialog.getByText('采购订单', { exact: true }).click()
  await expect(dialog.getByText('当前账号没有此操作权限', { exact: true })).toBeVisible()
  fail = false
  await dialog.getByRole('button', { name: '重新加载', exact: true }).click()
  await dialog.getByRole('combobox').click()
  await page.getByRole('option', { name: '当前供应商 · S1', exact: true }).click()
  await expect(dialog.getByText('当前供应商 · S1', { exact: true })).toBeVisible()
  await page.screenshot({
    path: testInfo.outputPath('supplier-recovered.png'),
    animations: 'disabled'
  })
  await dialog.getByRole('button', { name: '取消', exact: true }).click()
  await expect(dialog).not.toBeVisible()
  hold = true
  await page.getByRole('button', { name: '采购转单', exact: true }).click()
  await expect.poll(() => pending.length).toBe(1)
  await dialog.getByRole('button', { name: '取消', exact: true }).click()
  await expect(dialog).not.toBeVisible()
  await page.getByRole('button', { name: '采购转单', exact: true }).click()
  await expect(dialog.getByRole('combobox')).toBeVisible()
  await pending[0].fulfill({
    json: [{ id: 'old-supplier', supplier_name: '旧供应商', supplier_code: 'OLD' }]
  })
  await page.evaluate(
    () =>
      new Promise<void>((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
      )
  )
  await dialog.getByRole('combobox').click()
  await expect(page.getByRole('option', { name: '当前供应商 · S1', exact: true })).toBeVisible()
  await expect(page.getByRole('option', { name: '旧供应商 · OLD', exact: true })).toHaveCount(0)
  expect(errors).toEqual([])
})
