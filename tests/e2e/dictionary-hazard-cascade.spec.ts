import { expect, test, type Page } from '@playwright/test'

interface CascadeDictionaryCase {
  code: string
  typeName: string
  parentFieldLabel: string
  parentOption: string
}

const cascadeDictionaryCases: CascadeDictionaryCase[] = [
  {
    code: 'smisSecondaryHazardCategory',
    typeName: '二级隐患类别',
    parentFieldLabel: '上级字典项',
    parentOption: '基础管理'
  },
  {
    code: 'smisHazardContent',
    typeName: '隐患内容',
    parentFieldLabel: '上级字典项',
    parentOption: '事故隐患排查治理'
  }
]

async function openDictionaryType(page: Page, dictionary: CascadeDictionaryCase): Promise<void> {
  const treePanel = page.locator('.dict-tree-panel')
  await treePanel.getByPlaceholder('搜索目录名称或字典编码').fill(dictionary.code)

  const code = treePanel.locator('.dict-type-tree__code', { hasText: dictionary.code }).first()
  await expect(code).toBeVisible()
  await code.locator('xpath=ancestor::*[contains(@class,"dict-type-tree__node")]').click()

  const tablePanel = page.locator('.dict-table-panel')
  await expect(tablePanel).toContainText(dictionary.typeName)
  await tablePanel.getByRole('button', { name: '新增' }).first().click()
}

async function expectDialogScrollsInternally(page: Page): Promise<void> {
  const metrics = await page.locator('.art-dialog:visible').evaluate((dialog) => {
    const overlay = dialog.closest<HTMLElement>('.el-overlay-dialog')
    const scrollbar = dialog.querySelector<HTMLElement>(
      '.art-dialog__scrollbar .el-scrollbar__wrap'
    )
    const dialogRect = dialog.getBoundingClientRect()

    return {
      dialogTop: dialogRect.top,
      dialogBottom: dialogRect.bottom,
      viewportHeight: window.innerHeight,
      overlayClientHeight: overlay?.clientHeight ?? 0,
      overlayScrollHeight: overlay?.scrollHeight ?? 0,
      scrollbarClientHeight: scrollbar?.clientHeight ?? 0,
      scrollbarScrollHeight: scrollbar?.scrollHeight ?? 0
    }
  })

  expect(metrics.dialogTop).toBeGreaterThanOrEqual(0)
  expect(metrics.dialogBottom).toBeLessThanOrEqual(metrics.viewportHeight)
  expect(metrics.overlayScrollHeight).toBeLessThanOrEqual(metrics.overlayClientHeight + 1)
  expect(metrics.scrollbarScrollHeight).toBeGreaterThan(metrics.scrollbarClientHeight)
}

test('隐患三级字典可在数据字典中建立明确的父子关系', async ({ page }) => {
  test.setTimeout(90_000)
  await page.goto('/#/data-center/dict', { waitUntil: 'domcontentloaded' })
  await expect(page).not.toHaveURL(/#\/auth\/login/)
  await expect(page.locator('.dict-page')).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 60_000 })

  const treePanel = page.locator('.dict-tree-panel')
  const expandToggle = treePanel.locator('.dict-type-tree__expand-toggle')
  await expect(expandToggle).toHaveAccessibleName('全部展开字典目录')
  await expandToggle.click()
  await expect(expandToggle).toHaveAccessibleName('全部收起字典目录')
  await expandToggle.click()
  await expect(expandToggle).toHaveAccessibleName('全部展开字典目录')
  await expandToggle.click()
  await expect(expandToggle).toHaveAccessibleName('全部收起字典目录')

  await page.route('**/rest/v1/rpc/save_dict_type_tree_order', async (route) => {
    await route.fulfill({ status: 200, contentType: 'application/json', body: '' })
  })
  const hazardLevelNode = treePanel
    .locator('.dict-type-tree__code', { hasText: 'smisHazardLevel' })
    .locator('xpath=ancestor::*[contains(@class,"el-tree-node__content")]')
  const frequencyUnitNode = treePanel
    .locator('.dict-type-tree__code', { hasText: 'smisFrequencyUnit' })
    .locator('xpath=ancestor::*[contains(@class,"el-tree-node__content")]')
  await hazardLevelNode.dragTo(frequencyUnitNode, {
    targetPosition: { x: 24, y: 2 }
  })
  await expect(page.locator('.el-tree__drop-indicator')).toBeHidden()
  await expect(treePanel.locator('.is-drop-inner')).toHaveCount(0)
  await page.mouse.move(900, 500)
  await expect(page.locator('.el-tree__drop-indicator')).toBeHidden()
  await page.unroute('**/rest/v1/rpc/save_dict_type_tree_order')

  await treePanel.getByPlaceholder('搜索目录名称或字典编码').fill('vmsFleetHealthRisk')
  await expect(treePanel).toContainText('SMIS安全管理')
  await expect(treePanel).toContainText('安全生产')
  await expect(treePanel).toContainText('车队健康风险')

  for (const dictionary of cascadeDictionaryCases) {
    await openDictionaryType(page, dictionary)

    const dialog = page.getByRole('dialog', { name: '新增字典' })
    await expect(dialog).toBeVisible()
    await expect(dialog.locator('.art-dialog__scrollbar')).toBeVisible()
    await expectDialogScrollsInternally(page)
    await expect(dialog.getByText(dictionary.parentFieldLabel, { exact: true })).toBeVisible()

    const parentField = dialog
      .locator('.el-form-item')
      .filter({ hasText: dictionary.parentFieldLabel })
    await parentField.locator('.el-select').click()
    await expect(page.locator('.el-select-dropdown:visible')).toContainText(dictionary.parentOption)

    await page.keyboard.press('Escape')
    await dialog.getByRole('button', { name: '取消' }).click()
    await expect(dialog).toBeHidden()
  }
})
