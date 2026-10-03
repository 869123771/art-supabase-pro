import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })
test.setTimeout(120_000)

test('共享图标保留无障碍属性并更新动态样式和尺寸', async ({ page }, testInfo) => {
  await page.goto('/tests/e2e/fixtures/art-svg-icon-attrs.html')
  await expect(page.getByTestId('decorative-icon')).toHaveAttribute('aria-hidden', 'true')
  const icon = page.getByRole('img', { name: '已完成', exact: true })
  await expect(icon).toHaveClass(/compact/)
  await expect(icon).toHaveCSS('color', 'rgb(60, 70, 90)')
  await expect(icon).toHaveAttribute('width', '24')
  await page.getByRole('button', { name: '切换尺寸' }).click()
  const expanded = page.getByRole('img', { name: '已完成，大图标', exact: true })
  await expect(expanded).toHaveClass(/expanded/)
  await expect(expanded).not.toHaveClass(/compact/)
  await expect(expanded).toHaveCSS('color', 'rgb(20, 120, 80)')
  await expect(expanded).toHaveAttribute('width', '48')
  await expect(expanded.locator('path')).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('icon-attributes.png') })
})
