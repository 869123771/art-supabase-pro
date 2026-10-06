import { expect, test } from '@playwright/test'
import { prepareIsolatedSession } from './support/isolated-session'

test.use({ storageState: { cookies: [], origins: [] } })

for (const entry of ['bulk', 'row'] as const) {
  test(`${entry} 删除先核验，失败与取消保留选择，成功后刷新`, async ({ page }) => {
    await prepareIsolatedSession(page)
    let failInspection = true
    let deleted = false
    let deleteCalls = 0
    const events: string[] = []
    await page.route('**/rest/v1/mdm_production_department?**', (route) =>
      route.fulfill({
        json: [
          {
            id: 'root',
            tenant_id: 'permission-test-tenant',
            code: 'ROOT',
            name: '测试工厂',
            enabled: true
          },
          {
            id: 'shop',
            parent_id: 'root',
            tenant_id: 'permission-test-tenant',
            code: 'SHOP',
            name: '测试车间',
            enabled: true
          }
        ]
      })
    )
    await page.route('**/rest/v1/mdm_work_center?**', (route) =>
      route.fulfill({
        json: [
          {
            id: 'center',
            department_id: 'shop',
            tenant_id: 'permission-test-tenant',
            code: 'WC',
            name: '测试中心',
            sort: 1
          }
        ]
      })
    )
    await page.route('**/rest/v1/mdm_workstation?**', (route) => {
      if (route.request().method() === 'DELETE') {
        events.push('delete')
        deleteCalls++
        deleted = true
        return route.fulfill({
          headers: { 'content-range': '0-0/1', 'access-control-expose-headers': 'content-range' },
          json: [{ id: 'station' }]
        })
      }
      return route.fulfill({
        headers: {
          'content-range': deleted ? '*/0' : '0-0/1',
          'access-control-expose-headers': 'content-range'
        },
        json: deleted
          ? []
          : [
              {
                id: 'station',
                tenant_id: 'permission-test-tenant',
                department_id: 'shop',
                work_center_id: 'center',
                workstation_code: 'WS-001',
                workstation_name: '测试工位',
                enabled: true
              }
            ]
      })
    })
    await page.route('**/rest/v1/rpc/get_record_delete_dependency_details**', (route) => {
      events.push('inspect')
      expect(route.request().postDataJSON()).toMatchObject({
        p_table: 'mdm_workstation',
        p_ids: ['station']
      })
      return failInspection
        ? route.fulfill({ status: 403, json: { code: '42501', message: 'permission denied' } })
        : route.fulfill({ json: [] })
    })
    await page.goto('/tests/e2e/fixtures/workstation-delete.html')
    await expect(page.getByText('测试工位', { exact: true }).first()).toBeVisible()
    await page.locator('.el-table__header-wrapper .el-checkbox').first().click()
    const remove = page.getByLabel('批量操作').getByRole('button', { name: '删除', exact: true })
    const clickDelete = async () => {
      if (entry === 'bulk') await remove.click()
      else {
        await page.getByRole('button', { name: '更多操作', exact: true }).hover()
        await page.getByRole('menuitem', { name: '删除工位' }).click()
      }
    }
    await clickDelete()
    await expect(page.getByRole('alert')).toContainText('关联资料未完成核验')
    expect(deleteCalls).toBe(0)
    await expect(page.locator('.el-message-box')).toHaveCount(0)
    await page.screenshot({
      path: test.info().outputPath('inspection-error.png'),
      fullPage: true,
      animations: 'disabled'
    })
    failInspection = false
    await page.getByRole('button', { name: '重新检查', exact: true }).click()
    await expect(page.getByRole('button', { name: '重新检查', exact: true })).toHaveCount(0)
    await clickDelete()
    await expect(page.locator('.el-message-box')).toContainText('确定删除工位')
    await page.locator('.el-message-box').getByRole('button', { name: '取消', exact: true }).click()
    expect(deleteCalls).toBe(0)
    await expect(remove).toBeVisible()
    await clickDelete()
    await page.locator('.el-message-box').getByRole('button', { name: '删除', exact: true }).click()
    await expect.poll(() => deleteCalls).toBe(1)
    await expect(page.getByText('测试工位', { exact: true })).toHaveCount(0)
    expect(events).toEqual(['inspect', 'inspect', 'inspect', 'inspect', 'delete'])
  })
}
