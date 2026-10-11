import { expect, test } from '@playwright/test'
import { createClient, type SupabaseClient, type Session } from '@supabase/supabase-js'
import { loadEnv } from 'vite'
import { readFileSync } from 'node:fs'

let client: SupabaseClient
let session: Session
test.setTimeout(180_000)
test.beforeAll(async () => {
  const env = loadEnv('development', process.cwd(), '')
  expect(new URL(env.VITE_SUPABASE_URL).hostname).toBe('ckbftoopuyophiebamwy.supabase.co')
  client = createClient(env.VITE_SUPABASE_URL, env.VITE_SUPABASE_KEY, {
    auth: { persistSession: false }
  })
  const state = JSON.parse(readFileSync('playwright/.auth/user.json', 'utf8')) as {
    origins: { localStorage: { name: string; value: string }[] }[]
  }
  const saved = state.origins
    .flatMap((origin) => origin.localStorage)
    .find((item) => item.name === 'sb-ckbftoopuyophiebamwy-auth-token')
  const email = process.env.E2E_EMAIL
  const password = process.env.E2E_PASSWORD
  if (!email || !password)
    expect(saved, '已有真实测试会话或配置 E2E_EMAIL/E2E_PASSWORD').toBeTruthy()
  const { data, error } =
    email && password
      ? await client.auth.signInWithPassword({ email, password })
      : await client.auth.setSession(JSON.parse(saved!.value))
  expect(error, '真实测试账号登录').toBeNull()
  session = data.session!
})
test.beforeEach(async ({ page }) => {
  await page.addInitScript((session) => {
    localStorage.setItem('sb-ckbftoopuyophiebamwy-auth-token', JSON.stringify(session))
    const key = Object.keys(localStorage).find((key) => /^sys-v.*-user$/.test(key))
    if (key) {
      const user = JSON.parse(localStorage.getItem(key) || '{}')
      localStorage.setItem(
        key,
        JSON.stringify({
          ...user,
          accessToken: session.access_token,
          refreshToken: session.refresh_token
        })
      )
    }
  }, session)
})

test('真实 Data API 单据关联及全部选单来源', async () => {
  const source = readFileSync('modules/art-supabase-wms/src/api/initial-sales.ts', 'utf8')
  const select = source.match(/const documentSelect = `([\s\S]*?)`/)?.[1]
  expect(select).toBeTruthy()
  const { data: documents, error } = await client
    .from('wms_sales_document')
    .select(select!)
    .limit(12)
  expect(error, '销售单据完整关系查询').toBeNull()
  expect(documents?.length).toBeGreaterThan(0)
  const { data: warehouses, error: warehouseError } = await client
    .from('mdm_warehouse')
    .select('id,tenant_id,organization_id')
    .eq('status', 'enabled')
    .limit(1)
  expect(warehouseError).toBeNull()
  expect(warehouses?.length).toBe(1)
  const warehouse = warehouses![0]
  for (const kind of [
    'stock',
    'other_stock',
    'request_stock',
    'sales_order',
    'shipping_notice',
    'outbound',
    'return_request',
    'issue_request',
    'other_outbound'
  ]) {
    const result = await client.rpc('wms_sales_choices_secure', {
      p_kind: kind,
      p_tenant_id: warehouse.tenant_id,
      p_organization_id: warehouse.organization_id,
      p_warehouse_id: warehouse.id,
      p_keyword: null,
      p_limit: 10,
      p_offset: 0,
      p_exclude_document_id: null
    })
    expect(result.error, `真实选单 ${kind}`).toBeNull()
    expect(result.data).toHaveProperty('data')
    expect(result.data).toHaveProperty('total')
  }
})

for (const item of [
  { path: 'sales-outbound', title: '销售出库单', source: '销售订单' },
  { path: 'sales-return', title: '销售退货单', source: '销售出库单' },
  { path: 'other-outbound', title: '其他出库单', source: '出库申请单' },
  { path: 'outbound-request', title: '出库申请单', source: '' },
  { path: 'sales-invoice', title: '销售发票草稿', source: '' }
]) {
  test(`真实页面 ${item.title} 读取及新增参选`, async ({ page }, info) => {
    test.setTimeout(120_000)
    const failures: string[] = []
    page.on('response', (response) => {
      if (response.url().includes('/rest/v1/') && response.status() >= 400)
        failures.push(`${response.status()} ${new URL(response.url()).pathname}`)
    })
    await page.goto(`#/wms/outbound-business/${item.path}`)
    const table = page.locator('.art-table-query')
    await expect(table).toBeVisible({ timeout: 60_000 })
    await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 60_000 })
    const view = table.getByRole('button', { name: /查看/ }).first()
    if (['sales-outbound', 'sales-return', 'other-outbound'].includes(item.path)) {
      await expect(view).toBeVisible({ timeout: 90_000 })
    }
    if (await view.isVisible()) {
      await view.click()
      await expect(page.locator('.el-drawer:visible')).toBeVisible()
      await expect(page.locator('.el-drawer:visible .el-table')).toBeVisible({ timeout: 30_000 })
      await expect(page.getByText('销售单据加载失败，请重试', { exact: true })).toHaveCount(0)
      await page.screenshot({ path: info.outputPath(`${item.path}-live-detail.png`) })
      await page.keyboard.press('Escape')
      await expect(page.locator('.el-drawer:visible')).toHaveCount(0)
    }
    if (item.path !== 'sales-invoice') {
      await page.getByRole('button', { name: `新增${item.title}`, exact: true }).click()
      const drawer = page.locator('.el-drawer:visible')
      await expect(drawer).toBeVisible()
      if (item.path === 'sales-outbound') {
        await drawer.getByRole('combobox', { name: /仓库号/ }).click()
        await page.locator('.el-select-dropdown:visible .el-select-dropdown__item').first().click()
      }
      if (item.source) {
        await drawer.getByRole('button', { name: '选单', exact: true }).click()
        await page.getByText(item.source, { exact: true }).last().click()
        const picker = page.getByRole('dialog', { name: '选择来源明细', exact: true })
        await expect(picker).toBeVisible()
        await expect(picker.getByRole('button', { name: '确定', exact: true })).toBeEnabled({
          timeout: 30_000
        })
        await page.screenshot({ path: info.outputPath(`${item.path}-live-sources.png`) })
        await picker.getByRole('button', { name: '取消', exact: true }).click()
      }
      if (item.path === 'sales-return') {
        await drawer.getByRole('button', { name: '添加物料', exact: true }).click()
        const materials = page.getByRole('dialog', { name: '选择销售物料', exact: true })
        await expect(materials.locator('.el-table__body tr').first()).toBeVisible()
        await materials.locator('.el-table__header .el-checkbox').first().click()
        await materials.getByRole('button', { name: '确定', exact: true }).click()
        const lines = drawer.locator('.wms-editable-line-table')
        const count = await lines.locator('.el-table__body tr').count()
        expect(count).toBeGreaterThan(1)
        const operation = lines.getByRole('columnheader', { name: '操作', exact: true })
        await expect
          .poll(async () => (await operation.boundingBox())?.width || 0)
          .toBeLessThanOrEqual(150)
        const width = (await operation.boundingBox())!.width
        for (let remaining = count; remaining > 1; remaining--) {
          await lines.getByRole('button', { name: '更多操作', exact: true }).first().click()
          await page.getByRole('menuitem', { name: '删除明细', exact: true }).click()
          await expect(lines.locator('.el-table__body tr')).toHaveCount(remaining - 1)
          await expect
            .poll(async () => (await operation.boundingBox())?.width || 0)
            .toBeLessThanOrEqual(width + 1)
        }
        await page.screenshot({ path: info.outputPath('sales-return-live-deleted-lines.png') })
      }
      await drawer.getByRole('button', { name: '取消', exact: true }).click()
    }
    if (['sales-outbound', 'sales-return', 'other-outbound'].includes(item.path)) {
      await table.locator('.el-table__body .el-checkbox').first().click()
      await page.evaluate(() => {
        window.print = () => {}
      })
      await page.getByRole('button', { name: '批量打印', exact: true }).click()
      await expect(page.locator('.wms-sales-print-sheet')).toHaveCount(1)
    }
    expect(failures, '真实页面 Data API 错误').toEqual([])
  })
}

test('真实出库申请库存参选、暂存和删除闭环', async ({ page }) => {
  test.setTimeout(180_000)
  let createdId: string | undefined
  try {
    const { data: profile } = await client
      .from('sys_user')
      .select('tenant_id')
      .eq('auth_user_id', session.user.id)
      .single()
    const { data: warehouses, error: warehouseError } = await client
      .from('mdm_warehouse')
      .select('id,tenant_id,organization_id,warehouse_code')
      .eq('tenant_id', profile.tenant_id)
      .eq('status', 'enabled')
      .contains('business_scopes', ['picking'])
    expect(warehouseError).toBeNull()
    let stocked: { warehouseCode: string; organizationId: string } | undefined
    for (const warehouse of warehouses || []) {
      const { data, error } = await client.rpc('wms_sales_choices_secure', {
        p_kind: 'request_stock',
        p_tenant_id: warehouse.tenant_id,
        p_organization_id: warehouse.organization_id,
        p_warehouse_id: warehouse.id,
        p_limit: 1
      })
      expect(error).toBeNull()
      if (data.total > 0) {
        stocked = {
          warehouseCode: warehouse.warehouse_code,
          organizationId: warehouse.organization_id
        }
        break
      }
    }
    expect(stocked, '测试租户有可参选库存的领料仓库').toBeTruthy()
    const { data: organization } = await client
      .from('mdm_organization')
      .select('organization_name')
      .eq('id', stocked!.organizationId)
      .single()
    await page.goto('#/wms/outbound-business/outbound-request')
    await page.getByRole('button', { name: '新增出库申请单', exact: true }).click()
    const drawer = page.locator('.el-drawer:visible')
    await drawer.getByRole('combobox', { name: /库存组织/ }).click()
    await page
      .locator('.el-select-dropdown:visible .el-select-dropdown__item')
      .filter({ hasText: organization.organization_name })
      .first()
      .click()
    await drawer.getByRole('combobox', { name: /仓库号/ }).click()
    await page
      .locator('.el-select-dropdown:visible .el-select-dropdown__item')
      .filter({ hasText: stocked!.warehouseCode })
      .click()
    await drawer.getByRole('button', { name: '添加物料', exact: true }).click()
    const picker = page.getByRole('dialog', { name: '选择出库库存', exact: true })
    await expect(picker.locator('.el-table__body tr').first()).toBeVisible()
    await picker.locator('.el-table__body .el-checkbox').first().click()
    await picker.getByRole('button', { name: '确定', exact: true }).click()
    await expect(drawer.locator('.wms-editable-line-table .el-table__body tr')).toHaveCount(1)
    const response = page.waitForResponse(
      (response) =>
        response.url().includes('/rpc/wms_create_issue_request_secure') &&
        response.request().method() === 'POST'
    )
    await drawer.getByRole('button', { name: '保存', exact: true }).click()
    const saved = await response
    expect(saved.status()).toBe(200)
    createdId = await saved.json()
    expect(createdId).toMatch(/^[0-9a-f-]{36}$/)
    await expect(drawer).not.toBeVisible()
    const { data, error } = await client
      .from('wms_issue_request')
      .select('id,document_no,status,work_order_id')
      .eq('id', createdId)
      .single()
    expect(error).toBeNull()
    expect(data.status).toBe('draft')
    expect(data.work_order_id).toBeNull()
    expect(data.document_no).toMatch(/^CKSQ\d{6}-\d+$/)
    const row = page
      .locator('.art-table-query .el-table__body tr')
      .filter({ hasText: data.document_no })
    await expect(row).toBeVisible()
    await row.getByRole('button', { name: '更多操作', exact: true }).click()
    await page.getByRole('menuitem', { name: '删除', exact: true }).click()
    await page
      .getByRole('button', { name: /确定|确认删除/, exact: true })
      .last()
      .click()
    await expect(row).toHaveCount(0)
    createdId = undefined
  } finally {
    if (createdId) {
      const result = await client.rpc('wms_delete_issue_request_secure', {
        p_request_id: createdId
      })
      expect(result.error, '删除测试草稿').toBeNull()
    }
  }
})
