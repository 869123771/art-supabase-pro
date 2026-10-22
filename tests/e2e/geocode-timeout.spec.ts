import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })

for (const scenario of ['success', 'empty', 'invalid', 'timeout', 'throw'] as const) {
  test(`地址解析完成、失败和超时均恢复操作 ${scenario}`, async ({ page }) => {
    const errors: string[] = []
    page.on('pageerror', (error) => errors.push(error.message))
    await page.clock.install()
    await page.route('**/src/hooks/core/useAmapSdk.ts*', (route) =>
      route.fulfill({
        contentType: 'text/javascript',
        body: `export function useAmapSdk() {
          return { loadAmap: async () => ({ Geocoder: class {
            getLocation(address, callback) {
              const scenario = ${JSON.stringify(scenario)};
              if (scenario === 'timeout') return;
              if (scenario === 'throw') throw new Error('地址服务暂不可用，请稍后重试');
              callback(scenario === 'empty' ? 'no_data' : 'complete', {
                geocodes: [{ location: scenario === 'invalid'
                  ? { lng: 190, lat: 91 }
                  : { lng: 113.1234567, lat: 22.1234567 } }]
              });
            }
          } }) };
        }`
      })
    )
    await page.goto('/tests/e2e/fixtures/geocode-timeout.html')
    const action = page.getByRole('button', { name: '解析地址', exact: true })
    await action.click()
    if (scenario === 'timeout') {
      await expect(action).toBeDisabled()
      await page.clock.fastForward(10_001)
    }
    await expect(page.getByTestId('result')).toHaveText(
      scenario === 'success'
        ? '113.123457,22.123457'
        : scenario === 'timeout'
          ? '地址解析超时，请稍后重试'
          : scenario === 'throw'
            ? '地址服务暂不可用，请稍后重试'
            : '未找到地址'
    )
    await expect(action).toBeEnabled()
    expect(errors).toEqual([])
  })
}
