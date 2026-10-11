import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })
for (const feature of ['cargo', 'customer-address']) {
  test(`${feature} 批量先检查后确认且取消不报错`, async ({ page }) => {
    const events: string[] = []
    const id = '00000000-0000-4000-a000-000000000001'
    await page.route('**/rest/v1/**', async (route) => {
      const url = route.request().url()
      const row = {
        id,
        cargo_name: '测试货物',
        cargo_code: 'HW-001',
        region: '北京',
        address_detail: '测试地址',
        tenant_id: '11111111-1111-4111-a111-111111111111'
      }
      if (url.includes('get_governed_delete_dependency_details')) {
        events.push('inspect')
        return route.fulfill({ json: [] })
      }
      if (route.request().method() === 'DELETE') events.push('delete')
      if (url.includes('tms_list_customer_addresses_secure'))
        return route.fulfill({ json: { records: [row], total: 1 } })
      if (new URL(url).pathname.endsWith('/mdm_cargo'))
        return route.fulfill({
          json: [row],
          headers: { 'content-range': '0-0/1', 'access-control-expose-headers': 'content-range' }
        })
      return route.fulfill({ json: [] })
    })
    await page.goto(`/tests/e2e/fixtures/scrollbar-workspace.html?page=${feature}`)
    await expect(page.locator('.el-table__body-wrapper tr')).toHaveCount(1)
    await page.locator('.el-table__header-wrapper .el-checkbox').click()
    await page.getByRole('button', { name: '批量删除', exact: true }).click()
    const confirmation = page.locator('.el-message-box')
    await expect(confirmation).toBeVisible()
    expect(events).toEqual(['inspect'])
    await confirmation.getByRole('button', { name: '取消', exact: true }).click()
    await expect(confirmation).toBeHidden()
    await expect(page.locator('.el-message--error')).toHaveCount(0)
    expect(events).toEqual(['inspect'])
  })
}
