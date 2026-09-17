import { expect, test, type Page } from '@playwright/test'

async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const viewport = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }))
  expect(viewport.scrollWidth).toBeLessThanOrEqual(viewport.clientWidth + 1)
}

test('工作区刷新采用轻量图标并固定在业务按钮左侧', async ({ page }) => {
  test.setTimeout(120_000)
  const pageErrors: string[] = []
  page.on('pageerror', (error) => pageErrors.push(error.message))

  await page.goto('/#/dashboard/console', { waitUntil: 'domcontentloaded' })
  await expect(page).not.toHaveURL(/#\/auth\/login/)

  const header = page.locator('.business-workspace-header').first()
  await expect(header).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 60_000 })

  const actions = header.locator('.business-workspace-header__actions')
  const refresh = actions.getByRole('button', { name: '刷新运营数据' })
  const designReference = actions.locator('.page-design-reference')
  const designReferenceButton = designReference.getByRole('button', {
    name: /将本页作为设计参考|编辑本页设计参考/
  })
  await expect(refresh).toBeVisible()
  await expect(refresh).toHaveClass(/art-icon-button/)
  await expect(refresh).not.toHaveClass(/el-button/)
  await expect(designReferenceButton).toBeVisible()

  const ordering = await actions.evaluate((element) => {
    const children = [...element.children]
    const refreshIndex = children.findIndex((child) => child.classList.contains('art-icon-button'))
    const designReferenceIndex = children.findIndex((child) =>
      child.classList.contains('page-design-reference')
    )
    const businessButtonIndex = children.findIndex(
      (child) => child.classList.contains('el-button') && !child.closest('.page-design-reference')
    )
    return { refreshIndex, designReferenceIndex, businessButtonIndex }
  })
  expect(ordering.refreshIndex).toBe(0)
  expect(ordering.designReferenceIndex).toBe(ordering.refreshIndex + 1)
  expect(ordering.businessButtonIndex).toBeGreaterThan(ordering.designReferenceIndex)

  await designReferenceButton.click()
  await expect(page.getByText('记录你喜欢这页的原因')).toBeVisible()
  await expect(page.getByRole('checkbox', { name: '信息层级' })).toBeVisible()
  await expectNoHorizontalOverflow(page)
  await page.getByRole('button', { name: '关闭' }).click()

  await refresh.focus()
  await expect(refresh).toBeFocused()
  await expectNoHorizontalOverflow(page)
  expect(pageErrors).toEqual([])
})

test('全局固定操作栏保持提示在左、操作在右', async ({ page }) => {
  test.setTimeout(120_000)
  const pageErrors: string[] = []
  page.on('pageerror', (error) => pageErrors.push(error.message))

  await page.goto('/#/system/website-config', { waitUntil: 'domcontentloaded' })
  await expect(page).not.toHaveURL(/#\/auth\/login/)

  const actionBar = page.locator('.art-sticky-action-bar').first()
  await expect(actionBar).toBeVisible({ timeout: 60_000 })

  const summary = actionBar.locator('.art-sticky-action-bar__summary')
  const actions = actionBar.locator('.art-sticky-action-bar__actions')
  await expect(summary).toBeVisible()
  await expect(actions).toBeVisible()

  const layout = await actionBar.evaluate((element) => {
    const summaryElement = element.querySelector<HTMLElement>('.art-sticky-action-bar__summary')
    const actionsElement = element.querySelector<HTMLElement>('.art-sticky-action-bar__actions')
    const summaryRect = summaryElement?.getBoundingClientRect()
    const actionsRect = actionsElement?.getBoundingClientRect()
    return {
      direction: getComputedStyle(element).flexDirection,
      summaryLeft: summaryRect?.left ?? 0,
      actionsLeft: actionsRect?.left ?? 0,
      actionsRight: actionsRect?.right ?? 0,
      barRight: element.getBoundingClientRect().right
    }
  })

  if (layout.direction === 'row') {
    expect(layout.actionsLeft).toBeGreaterThan(layout.summaryLeft)
  }
  expect(layout.barRight - layout.actionsRight).toBeLessThanOrEqual(32)
  await expectNoHorizontalOverflow(page)
  expect(pageErrors).toEqual([])
})
