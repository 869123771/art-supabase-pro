import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })
test.setTimeout(120_000)

test('盘点表单提交编辑后的零值，重新打开恢复原始数量', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(error.message))
  await page.route('**/rest/v1/**', (route) => route.fulfill({ json: [] }))
  let payload: unknown
  await page.route('**/rest/v1/rpc/wms_record_count_line_secure', async (route) => {
    payload = route.request().postDataJSON()
    await route.fulfill({ json: true })
  })
  await page.goto('/tests/e2e/fixtures/wms-count-form.html')
  await page.getByRole('button', { name: '打开测试盘点' }).click()
  const dialog = page.getByRole('dialog')
  const quantity = dialog.getByRole('spinbutton')
  await expect.poll(async () => Number(await quantity.inputValue())).toBe(2)
  await quantity.fill('0')
  await quantity.blur()
  await dialog.getByRole('button', { name: '确定', exact: true }).click()
  await expect(page.getByTestId('saved-count')).toHaveText('1')
  expect(payload).toEqual({
    p_line_id: '11111111-1111-4111-8111-111111111111',
    p_counted_quantity: 0,
    p_counted_serial_ids: [],
    p_new_serial_nos: []
  })
  await expect(dialog).not.toBeVisible()
  await page.getByRole('button', { name: '打开测试盘点' }).click()
  await expect.poll(async () => Number(await dialog.getByRole('spinbutton').inputValue())).toBe(2)
  expect(errors).toEqual([])
})
