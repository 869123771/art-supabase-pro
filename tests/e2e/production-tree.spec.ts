import { expect, test } from '@playwright/test'
import { prepareIsolatedSession } from './support/isolated-session'

test.use({ storageState: { cookies: [], origins: [] } })
test.setTimeout(180_000)

for (const scenario of ['workstation', 'task', 'gantt'] as const) {
  test(`${scenario} 车间包含下级班组的工作中心`, async ({ page }, info) => {
    const errors: string[] = []
    page.on('pageerror', (error) => errors.push(error.message))
    await prepareIsolatedSession(page)
    await page.route('**/rest/v1/**', (route) => {
      const resource = new URL(route.request().url()).pathname.split('/').at(-1)
      return route.fulfill({
        json:
          resource === 'mdm_production_department'
            ? [
                {
                  id: 'factory',
                  tenant_id: 'test-tenant',
                  parent_id: null,
                  name: '测试工厂',
                  code: 'F',
                  enabled: true,
                  sort: 1
                },
                {
                  id: 'workshop',
                  tenant_id: 'test-tenant',
                  parent_id: 'factory',
                  name: '装配车间',
                  code: 'W',
                  enabled: true,
                  sort: 2
                },
                {
                  id: 'team',
                  tenant_id: 'test-tenant',
                  parent_id: 'workshop',
                  name: '装配班组',
                  code: 'T',
                  enabled: true,
                  sort: 3
                }
              ]
            : resource === 'mdm_work_center'
              ? [
                  {
                    id: 'center',
                    tenant_id: 'test-tenant',
                    department_id: 'team',
                    code: 'WC-TEAM',
                    name: '班组工作中心',
                    sort: 1,
                    headcount: 1,
                    daily_capacity_minutes: 480,
                    efficiency_percent: 100,
                    utilization_percent: 100,
                    parallel_capacity: 1
                  }
                ]
              : resource === 'mes_work_order_references'
                ? {
                    materials: [],
                    customers: [],
                    projects: [],
                    documentTypes: [],
                    employees: [],
                    workCenters: []
                  }
                : resource?.includes('list_operation_tasks')
                  ? { records: [], total: 0 }
                  : [],
        headers: { 'content-range': '*/0' }
      })
    })
    await page.goto(`/tests/e2e/fixtures/production-tree.html?scenario=${scenario}`)
    const navigator = page.locator('.production-work-center-navigator')
    await expect(navigator).toBeVisible({ timeout: 60_000 })
    await navigator.getByRole('combobox', { name: '车间 / 产线', exact: true }).click()
    const workshop = page
      .getByRole('option')
      .filter({ has: page.getByText('装配车间', { exact: true }) })
    await expect(workshop).toBeVisible()
    await expect(workshop).toContainText('测试工厂 / 装配车间')
    await workshop.click()
    await expect(navigator.getByRole('button', { name: /WC-TEAM.*班组工作中心/ })).toBeVisible()
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
    ).toBeLessThanOrEqual(1)
    await page.screenshot({ path: info.outputPath(`${scenario}-department-tree.png`) })
    expect(errors).toEqual([])
  })
}
