import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })
test('未加载的编号保留显示和值，不冒充完整业务记录', async ({ page }) => {
  await page.goto('/tests/e2e/fixtures/data-select-loading.html?single=unresolved')
  await expect(page.getByRole('textbox')).toHaveValue('not-loaded')
  await page.getByRole('button', { name: '打开选择器' }).click()
  const dialog = page.getByRole('dialog', { name: '单选分页测试' })
  await expect(dialog.getByText('暂无数据', { exact: true })).toBeVisible()
  await dialog.getByRole('button', { name: '确定', exact: true }).click()
  await expect(page.getByTestId('selector-result')).toHaveText(
    '{"value":"not-loaded","records":[]}'
  )
})
