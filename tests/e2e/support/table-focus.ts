import { expect, type Page, type TestInfo } from '@playwright/test'

/** Verify the shared focus contract against the rendered business workspace. */
export async function assertTableFocusContract(
  page: Page,
  testInfo: TestInfo,
  contextSelectors: string[] = []
) {
  const query = page.locator('.art-table-query:visible')
  const header = page.locator('.business-workspace-header')
  const search = query.locator('.art-search-bar').first()
  const searchWasVisible = await search.isVisible()
  await expect(query).toHaveCount(1)
  await expect(header).toBeVisible()
  const initialBox = await query.boundingBox()
  if (!initialBox) throw new Error('无法读取表格工作区位置')
  await expect(
    query
      .locator(
        'xpath=ancestor::*[contains(concat(" ", normalize-space(@class), " "), " art-page-view ")]'
      )
      .first()
  ).toBeVisible()

  const enter = async () => {
    await page.getByRole('switch', { name: '进入专注模式', exact: true }).locator('..').click()
    await expect(query).toHaveClass(/is-focus-mode/)
    await expect(header).toBeHidden()
    await expect
      .poll(async () => (await query.boundingBox())?.y ?? Infinity)
      .toBeLessThan(initialBox.y)
    await expect(query.locator('.el-table')).toBeVisible()
    await expect(query.locator('.el-pagination')).toBeVisible()
    for (const selector of contextSelectors) await expect(page.locator(selector)).toBeVisible()
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)
    ).toBeLessThanOrEqual(1)
  }
  const restored = async () => {
    await expect(query).not.toHaveClass(/is-focus-mode/)
    await expect(header).toBeVisible()
    await expect.poll(() => search.isVisible()).toBe(searchWasVisible)
    await expect
      .poll(async () => Math.abs(((await query.boundingBox())?.y ?? Infinity) - initialBox.y))
      .toBeLessThanOrEqual(1)
  }

  await enter()
  await page.screenshot({ path: testInfo.outputPath('table-focus.png'), animations: 'disabled' })
  if (contextSelectors.length && (page.viewportSize()?.width ?? 1440) < 980) {
    const scrollPositions = await query.evaluate((node) => {
      const positions: number[] = []
      for (let parent = node.parentElement; parent; parent = parent.parentElement)
        positions.push(parent.scrollTop)
      return positions
    })
    await query.locator('.el-pagination').scrollIntoViewIfNeeded()
    await expect(query.locator('.el-pagination')).toBeInViewport()
    await page.screenshot({
      path: testInfo.outputPath('table-focus-lower.png'),
      animations: 'disabled'
    })
    await query.evaluate((node, positions) => {
      let index = 0
      for (let parent = node.parentElement; parent; parent = parent.parentElement)
        parent.scrollTop = positions[index++]
    }, scrollPositions)
  }
  await page.getByRole('button', { name: '退出专注模式', exact: true }).click()
  await restored()
  await enter()
  await page.keyboard.press('Escape')
  await restored()
}
