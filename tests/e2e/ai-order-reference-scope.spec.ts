import { expect, test } from '@playwright/test'

const previewPath = '/tests/e2e/fixtures/ai-order-reference-scope.html'
const platformTenantId = '55555555-5555-4555-8555-555555555555'
const platformCustomerId = '66666666-6666-4666-8666-666666666666'

test('全部租户智能填单只匹配默认平台租户的主数据', async ({ page }) => {
  test.setTimeout(60_000)
  const requests: Array<{ path: string; tenantFilter: string | null; body: string | null }> = []

  await page.route('**/rest/v1/**', async (route) => {
    const request = route.request()
    const url = new URL(request.url())
    requests.push({
      path: url.pathname,
      tenantFilter: url.searchParams.get('tenant_id'),
      body: request.postData()
    })

    if (url.pathname.endsWith('/rpc/tms_list_customer_options_secure')) {
      await route.fulfill({
        status: 200,
        json: [{ id: platformCustomerId, customer_name: '平台客户' }]
      })
      return
    }
    if (url.pathname.endsWith('/mdm_station') || url.pathname.endsWith('/mdm_cargo')) {
      await route.fulfill({ status: 200, json: [] })
      return
    }
    await route.fulfill({ status: 500, json: { message: 'unexpected reference request' } })
  })

  await page.goto(previewPath, { waitUntil: 'domcontentloaded' })
  const result = page.locator('#reference-result')
  await expect(result).toContainText(`"id":"${platformCustomerId}"`, { timeout: 45_000 })
  await expect(result).toContainText('"originStation":{"label":"平台发货站","status":"unmatched"}')

  const stationRequest = requests.find((request) => request.path.endsWith('/mdm_station'))
  const cargoRequest = requests.find((request) => request.path.endsWith('/mdm_cargo'))
  const customerRequest = requests.find((request) =>
    request.path.endsWith('/rpc/tms_list_customer_options_secure')
  )
  expect(stationRequest?.tenantFilter).toBe(`eq.${platformTenantId}`)
  expect(cargoRequest?.tenantFilter).toBe(`eq.${platformTenantId}`)
  expect(customerRequest?.body).toContain(`"p_tenant_id":"${platformTenantId}"`)
  expect(
    requests.some((request) => request.path.endsWith('/rpc/tms_list_customer_selector_secure'))
  ).toBe(false)
})
