import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })

test('生产与库存分页入口在网络请求前拒绝非法范围', async ({ page }) => {
  const requests: string[] = []
  await page.route('**/rest/v1/**', (route) => {
    requests.push(route.request().url())
    return route.fulfill({ json: [] })
  })
  await page.goto('/tests/e2e/fixtures/production-pagination.html')
  await page.getByRole('button', { name: '校验非法分页' }).click()
  await expect(page.getByTestId('result')).toHaveText('185 个参数拒绝')
  expect(requests).toEqual([])
})

test('有效第二页保留表查询与 RPC 的分页范围', async ({ page }) => {
  let calls = 0
  await page.route('**/rest/v1/**', (route) => {
    const url = new URL(route.request().url())
    calls++
    if (url.pathname.includes('/rpc/')) {
      const body = route.request().postDataJSON()
      if (/\/wms_project_(serial|pack|material|movement)_page_secure$/.test(url.pathname))
        expect(body).toMatchObject({ p_offset: 20, p_limit: 20 })
      else expect(body).toMatchObject({ p_from: 20, p_to: 39 })
    } else {
      expect(url.searchParams.get('offset')).toBe('20')
      expect(url.searchParams.get('limit')).toBe('20')
      expect(route.request().headers().prefer).toContain('count=exact')
    }
    return route.fulfill({
      headers: { 'content-range': '*/0', 'access-control-expose-headers': 'content-range' },
      json: []
    })
  })
  await page.goto('/tests/e2e/fixtures/production-pagination.html?valid=true')
  await page.getByRole('button', { name: '校验非法分页' }).click()
  await expect(page.getByTestId('result')).toHaveText('37 个请求完成')
  expect(calls).toBe(37)
})
