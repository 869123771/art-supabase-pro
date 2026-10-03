import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })
test.setTimeout(120_000)

test('工序关联使用租户精确计数且限制并发', async ({ page }) => {
  const rows = Array.from({ length: 7 }, (_, index) => ({
    id: `step-${index}`,
    tenant_id: `tenant-${index % 2}`
  }))
  let active = 0
  let peak = 0
  const counts: URL[] = []
  await page.route('**/rest/v1/**', async (route) => {
    const url = new URL(route.request().url())
    if (url.pathname.endsWith('/mdm_process_route_step')) {
      await route.fulfill({
        headers: { 'content-range': '0-6/7', 'access-control-expose-headers': 'content-range' },
        json: rows
      })
      return
    }
    counts.push(url)
    expect(route.request().method()).toBe('HEAD')
    expect(route.request().headers().prefer).toContain('count=exact')
    const index = Number(url.searchParams.get('process_route_step_id')?.replace('eq.step-', ''))
    expect(url.searchParams.get('tenant_id')).toBe(`eq.tenant-${index % 2}`)
    active += 1
    peak = Math.max(peak, active)
    await new Promise((resolve) => setTimeout(resolve, 50))
    await route.fulfill({
      headers: {
        'content-range': `*/${index === 0 ? 10001 : index}`,
        'access-control-expose-headers': 'content-range'
      },
      body: ''
    })
    active -= 1
  })
  await page.goto('/tests/e2e/fixtures/process-step-counts.html')
  await page.getByRole('button', { name: '查询工序' }).click()
  await expect(page.getByTestId('step-result')).toContainText('componentAssignmentCount')
  const result = JSON.parse(await page.getByTestId('step-result').innerText())
  expect(
    result.data.map((row: { componentAssignmentCount: number }) => row.componentAssignmentCount)
  ).toEqual([10001, 1, 2, 3, 4, 5, 6])
  expect(result.data.map((row: { id: string }) => row.id)).toEqual(rows.map((row) => row.id))
  expect(counts).toHaveLength(7)
  expect(result.total).toBe(7)
  expect(peak).toBe(3)
})

test('关联计数失败时不返回部分工序统计', async ({ page }) => {
  let counts = 0
  await page.route('**/rest/v1/**', async (route) => {
    const url = new URL(route.request().url())
    if (url.pathname.endsWith('/mdm_process_route_step')) {
      await route.fulfill({
        json: Array.from({ length: 7 }, (_, index) => ({
          id: `step-${index}`,
          tenant_id: 'tenant-a'
        }))
      })
      return
    }
    counts += 1
    if (url.searchParams.get('process_route_step_id') === 'eq.step-0') {
      await route.fulfill({ status: 500, body: '' })
    } else {
      await new Promise((resolve) => setTimeout(resolve, 100))
      await route.fulfill({
        headers: { 'content-range': '*/1', 'access-control-expose-headers': 'content-range' },
        body: ''
      })
    }
  })
  await page.goto('/tests/e2e/fixtures/process-step-counts.html')
  await page.getByRole('button', { name: '查询工序' }).click()
  await expect(page.getByTestId('step-result')).toHaveText('查询失败')
  expect(counts).toBe(3)
})
