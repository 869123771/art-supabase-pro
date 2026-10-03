import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })
test.setTimeout(120_000)

for (const empty of [false, true]) {
  test(`调用方加载状态控制选择器${empty ? '空结果' : '选择确认'}`, async ({ page }, testInfo) => {
    const errors: string[] = []
    page.on('pageerror', (error) => errors.push(error.message))
    await page.goto(`/tests/e2e/fixtures/data-select-loading.html${empty ? '?empty' : ''}`)
    await page.getByRole('button', { name: '打开选择器' }).click()
    const dialog = page.getByRole('dialog', { name: '选择测试明细' })
    const content = dialog.locator('.art-data-select-dialog__content')
    await expect(content).toHaveAttribute('aria-busy', 'true')
    await expect(dialog.getByRole('button', { name: '确定', exact: true })).toBeDisabled()
    await expect(dialog.getByText('暂无可选明细', { exact: true })).toBeHidden()
    await expect(dialog.getByRole('button', { name: '维护测试明细' })).toBeHidden()
    await page.screenshot({
      path: `.artifacts/data-select-loading-${testInfo.project.name}.png`,
      animations: 'disabled'
    })
    await page
      .getByRole('button', { name: '完成数据加载' })
      .evaluate((button: HTMLButtonElement) => button.click())
    await expect(content).toHaveAttribute('aria-busy', 'false')
    await expect(dialog.getByRole('button', { name: '确定', exact: true })).toBeEnabled()
    if (empty) {
      await expect(dialog.getByText('暂无可选明细', { exact: true })).toBeVisible()
      await expect(dialog.getByText('当前业务没有可选择的明细。', { exact: true })).toBeVisible()
      const emptyAction = dialog.getByRole('button', { name: '维护测试明细' })
      const actionBounds = await emptyAction.boundingBox()
      const contentBounds = await content.boundingBox()
      expect(actionBounds).not.toBeNull()
      expect(contentBounds).not.toBeNull()
      if (actionBounds && contentBounds) {
        expect(actionBounds.y).toBeGreaterThanOrEqual(contentBounds.y)
        expect(actionBounds.y + actionBounds.height).toBeLessThanOrEqual(
          contentBounds.y + contentBounds.height
        )
      }
      await dialog.getByRole('button', { name: '维护测试明细' }).click()
      await expect(page.getByTestId('selector-result')).toHaveText('maintenance-requested')
      await page.screenshot({
        path: `.artifacts/data-select-empty-${testInfo.project.name}.png`,
        animations: 'disabled'
      })
      await dialog.getByRole('button', { name: '取消', exact: true }).click()
    } else {
      await expect(dialog.getByText('测试可选明细', { exact: true })).toBeVisible()
      await dialog.locator('.el-table__body-wrapper .el-checkbox').first().click()
      await dialog.getByRole('button', { name: '确定', exact: true }).click()
      await expect(page.getByTestId('selector-result')).toHaveText('["fixture-line"]')
    }
    await expect(dialog).toBeHidden()
    expect(errors).toEqual([])
  })
}
