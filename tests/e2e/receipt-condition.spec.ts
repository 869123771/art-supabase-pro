import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] }, actionTimeout: 15000 })
test.setTimeout(60000)

test('两条收款条件新增、编辑停用、保存失败恢复与引用保护', async ({ page }, info) => {
  const records: Array<{
    id: string
    condition_code: string
    name: string
    due_days: number
    is_enabled: boolean
    remark: string
  }> = []
  const saves: Array<Record<string, unknown>> = []
  const deletes: string[][] = []
  let fail = true
  let blocked = true
  await page.route('**/rest/v1/**', (route) => {
    const url = new URL(route.request().url())
    const name = url.pathname.split('/').at(-1)
    const body = route.request().postDataJSON()
    if (name === 'sys_dictionary')
      return route.fulfill({
        json: [true, false].map((value) => ({
          id: String(value),
          code: String(value),
          value: String(value),
          label: value ? '是' : '否',
          status: '1',
          dict_type_table: { code: 'commonBoolean' }
        }))
      })
    if (name === 'fms_receivable_workspace_secure') {
      const ids = body.p_query?.ids as string[] | undefined
      const rows = ids ? records.filter((row) => ids.includes(row.id)) : records
      return route.fulfill({ json: { records: rows, total: rows.length } })
    }
    if (name === 'fms_save_receipt_condition_secure') {
      saves.push(body.p_payload)
      if (fail)
        return route.fulfill({
          status: 400,
          json: { code: 'P0001', message: '收款条件保存失败，请重试' }
        })
      const payload = body.p_payload
      const record = {
        id: payload.id || `condition-${records.length + 1}`,
        condition_code: payload.code,
        name: payload.name,
        due_days: payload.dueDays,
        is_enabled: payload.isEnabled,
        remark: payload.remark
      }
      const index = records.findIndex((row) => row.id === payload.id)
      if (index < 0) records.push(record)
      else records[index] = record
      return route.fulfill({ json: record.id })
    }
    if (name === 'fms_ar_delete_dependencies_secure')
      return route.fulfill({
        json: blocked
          ? [
              {
                resource_id: 'condition-1',
                dependency_code: 'financial',
                record_id: 'financial',
                target_id: 'financial',
                record_no: 'QA-CONDITION-AR-001',
                record_summary: '引用本账期的财务应收',
                record_status: 'approved',
                cleanup_allowed: false
              }
            ]
          : []
      })
    if (name === 'fms_delete_ar_records_secure') {
      expect(body.p_kind).toBe('condition')
      deletes.push(body.p_ids)
      records.splice(0, records.length)
      return route.fulfill({ json: null })
    }
    return route.fulfill({ json: [] })
  })
  const theme = info.project.use.colorScheme === 'dark' ? 'dark' : 'light'
  await page.goto(`/tests/e2e/fixtures/receivable-workspace.html?kind=condition&theme=${theme}`)
  for (const index of [1, 2]) {
    const attemptsBefore = saves.length
    await page.getByRole('button', { name: '新增', exact: true }).click()
    const dialog = page.getByRole('dialog')
    await dialog.getByRole('button', { name: '保存收款条件' }).click()
    expect(saves).toHaveLength(attemptsBefore)
    await dialog.getByRole('textbox', { name: '编号' }).fill(`QA-TERM-${index}`)
    await dialog.getByRole('textbox', { name: '名称' }).fill(`验收账期${index}`)
    await dialog.getByRole('spinbutton', { name: '账期天数' }).fill(String(index * 30))
    await dialog.getByRole('textbox', { name: '描述' }).fill(`仅演示账期${index}`)
    await dialog.getByRole('button', { name: '保存收款条件' }).click()
    if (index === 1) {
      await expect(page.locator('.el-message--error')).toHaveCount(1)
      await expect(dialog.getByRole('textbox', { name: '名称' })).toHaveValue('验收账期1')
      fail = false
      await dialog.getByRole('button', { name: '保存收款条件' }).click()
    }
    await expect(dialog).not.toBeVisible()
    const row = page.getByRole('row').filter({ hasText: `QA-TERM-${index}` })
    await expect(row).toContainText('启用')
    await row.getByRole('button', { name: '编辑', exact: true }).click()
    await dialog.getByText('否', { exact: true }).click()
    await dialog.getByRole('textbox', { name: '名称' }).fill(`验收账期${index}已复核`)
    if (index === 2) {
      await expect(page.locator('.el-message')).toHaveCount(0)
      await dialog.screenshot({ path: info.outputPath('condition-editor.png') })
    }
    await dialog.getByRole('button', { name: '保存收款条件' }).click()
    await expect(dialog).not.toBeVisible()
    await expect(row).toContainText('停用')
    await expect(row).toContainText(`验收账期${index}已复核`)
  }
  await expect(page.locator('.el-message')).toHaveCount(0)
  await page.screenshot({ path: info.outputPath('conditions-two-records.png'), fullPage: true })
  await page.locator('.el-table__header-wrapper label.el-checkbox').first().click()
  await page.getByRole('button', { name: '批量删除', exact: true }).click()
  await expect(page.getByRole('dialog')).toContainText('QA-CONDITION-AR-001')
  await page.screenshot({ path: info.outputPath('condition-reference.png'), fullPage: true })
  expect(deletes).toEqual([])
  await page.getByRole('dialog').getByRole('button', { name: '关闭', exact: true }).click()
  blocked = false
  await page.getByRole('button', { name: '批量删除', exact: true }).click()
  await page.locator('.el-message-box').getByRole('button', { name: '删除', exact: true }).click()
  await expect(page.getByText('暂无收款条件', { exact: true })).toBeVisible()
  expect(deletes).toEqual([['condition-1', 'condition-2']])
  expect(saves[0]).toMatchObject({ id: null, code: 'QA-TERM-1', dueDays: 30 })
  await expect(page.locator('.el-message')).toHaveCount(0)
  await page.screenshot({ path: info.outputPath('conditions-deleted.png'), fullPage: true })
})

test('收款条件删除重读缺少所选记录时停止，不能跳过未核验记录', async ({ page }) => {
  let checks = 0
  let deletes = 0
  const records = [1, 2].map((index) => ({
    id: `condition-${index}`,
    condition_code: `QA-TERM-${index}`,
    name: `验收账期${index}`,
    due_days: index * 30,
    is_enabled: true
  }))
  await page.route('**/rest/v1/**', (route) => {
    const name = new URL(route.request().url()).pathname.split('/').at(-1)
    const body = route.request().postDataJSON()
    if (name === 'fms_receivable_workspace_secure')
      return route.fulfill({
        json: {
          records: body.p_query?.ids ? records.slice(0, 1) : records,
          total: body.p_query?.ids ? 1 : 2
        }
      })
    if (name === 'fms_ar_delete_dependencies_secure') checks++
    if (name === 'fms_delete_ar_records_secure') deletes++
    return route.fulfill({ json: [] })
  })
  await page.goto('/tests/e2e/fixtures/receivable-workspace.html?kind=condition')
  await page.locator('.el-table__header-wrapper label.el-checkbox').first().click()
  await page.getByRole('button', { name: '批量删除', exact: true }).click()
  await expect(page.locator('.el-message--error')).toContainText('所选收款条件已变化')
  await expect(page.locator('.el-message-box')).toHaveCount(0)
  expect(checks).toBe(0)
  expect(deletes).toBe(0)
})
