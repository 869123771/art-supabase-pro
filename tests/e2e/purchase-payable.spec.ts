import { expect, test } from '@playwright/test'
test.use({ storageState: { cookies: [], origins: [] }, actionTimeout: 15000 })
for (const kind of ['estimated', 'financial'] as const) {
  test(`${kind} 两条应付数据、明细查看、错误重试和专注模式`, async ({ page }, testInfo) => {
    let fail = false
    const data = [1, 2].map((n) => ({
      id: `payable-${n}`,
      tenant_id: '11111111-1111-4111-8111-111111111111',
      kind,
      document_no: `${kind === 'estimated' ? 'ZGYF' : 'CWYF'}-202610-${n}`,
      source_document_id: `inbound-${n}`,
      source_document_no: `CGRK202610-${n}`,
      supplier_name: `项目供应商${n}`,
      business_date: '2026-10-10',
      status: 'draft',
      amount: 100 * n,
      tax_amount: 13 * n,
      total_amount: 113 * n,
      lines: [
        {
          id: `line-${n}`,
          source_line_id: `inbound-line-${n}`,
          line_no: 10,
          material_code: `MAT-${n}`,
          material_description: `项目物料${n}`,
          project_name: '机房装修工程',
          construction_no: null,
          unit_name: '件',
          quantity: 10 * n,
          unit_price: 10,
          amount: 100 * n,
          tax_amount: 13 * n,
          total_amount: 113 * n
        }
      ]
    }))
    const errors: string[] = []
    page.on('pageerror', (e) => errors.push(e.message))
    await page.route('**/rest/v1/**', (route) => {
      const name = new URL(route.request().url()).pathname.split('/').at(-1)
      if (name === 'fms_purchase_payable_list_secure')
        return fail
          ? route.fulfill({ status: 500, json: { code: 'XX000', message: 'internal error' } })
          : route.fulfill({ json: { data, total: 2 } })
      return route.fulfill({ json: [], headers: { 'content-range': '*/0' } })
    })
    await page.goto(`/tests/e2e/fixtures/purchase-payable.html?kind=${kind}`)
    const rows = page.locator('.el-table__body-wrapper tbody tr')
    await expect(rows).toHaveCount(2)
    await expect(page.getByRole('textbox', { name: '组合查询' })).toBeVisible()
    await page.getByRole('switch', { name: '进入专注模式', exact: true }).locator('..').click()
    await page.keyboard.press('Escape')
    await expect(
      page.getByRole('heading', {
        name: kind === 'estimated' ? '暂估应付单' : '财务应付单',
        exact: true
      })
    ).toBeVisible()
    await page.screenshot({ path: testInfo.outputPath(`${kind}-list.png`), fullPage: true })
    await page.getByRole('button', { name: '查看', exact: true }).first().click()
    const drawer = page.getByRole('dialog')
    await expect(drawer).toContainText('来源采购入库单：CGRK202610-1')
    await expect(drawer).toContainText('项目物料1')
    await page.screenshot({ path: testInfo.outputPath(`${kind}-detail.png`), fullPage: true })
    await page.keyboard.press('Escape')
    fail = true
    await page.getByRole('button', { name: '查询', exact: true }).click()
    await expect(page.getByText('数据加载失败', { exact: true })).toBeVisible()
    fail = false
    const retry = page.getByRole('button', { name: /重试|重新加载/ })
    if (await retry.count()) await retry.first().click()
    else await page.getByRole('button', { name: '查询', exact: true }).click()
    await expect(rows).toHaveCount(2)
    expect(errors).toEqual([])
  })
}
