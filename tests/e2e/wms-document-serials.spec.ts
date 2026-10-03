import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })

for (const { kind, trigger } of [
  { kind: 'sales', trigger: '打开销售单据' },
  { kind: 'purchase', trigger: '打开采购单据' }
] as const) {
  test(`${kind === 'sales' ? '销售' : '采购'}单据序列号弹窗显示统一空态并可导入文本`, async ({
    page,
    request
  }, testInfo) => {
    test.setTimeout(180_000)
    await page.route('**/rest/v1/**', (route) =>
      route.fulfill({ contentType: 'application/json', body: '[]' })
    )
    const fixturePath = '/tests/e2e/fixtures/wms-document-serials.html'
    await expect
      .poll(async () => (await request.get(fixturePath)).text(), { timeout: 90_000 })
      .toContain('<title>仓储单据序列号验收</title>')
    await page.goto(fixturePath, {
      waitUntil: 'domcontentloaded'
    })
    await expect(page).toHaveTitle('仓储单据序列号验收')
    if (testInfo.project.name.includes('dark')) {
      await page.evaluate(() => document.documentElement.classList.add('dark'))
    }
    if (testInfo.project.name.includes('shadow')) {
      await page.evaluate(() =>
        document.documentElement.setAttribute('data-box-mode', 'shadow-mode')
      )
    }

    await page.getByRole('button', { name: trigger }).click()
    const drawer = page.locator('.el-drawer')
    await drawer.getByRole('button', { name: '编辑' }).click()
    const lineDialog = page.getByRole('dialog', { name: '编辑物料明细' })
    await lineDialog.getByRole('button', { name: '查看序列号' }).click()
    const serialDialog = page.getByRole('dialog', { name: '查看序列号' })
    await expect(serialDialog.locator('.art-empty-state')).toBeVisible()
    await expect(serialDialog.getByText('暂无序列号')).toBeVisible()
    await expect(serialDialog.getByText('录入或导入序列号后可在这里查看。')).toBeVisible()

    const widths = await page.evaluate(() => ({
      viewport: document.documentElement.clientWidth,
      content: document.documentElement.scrollWidth
    }))
    expect(widths.content).toBeLessThanOrEqual(widths.viewport + 1)
    await page.screenshot({
      path: `.artifacts/wms-${kind}-serials-empty-${testInfo.project.name}.png`,
      animations: 'disabled'
    })

    await serialDialog.getByRole('button', { name: 'Close' }).click()
    const fileInput = lineDialog.locator('input[type="file"][accept=".txt,.csv"]')
    await fileInput.setInputFiles({
      name: 'empty.txt',
      mimeType: 'text/plain',
      buffer: Buffer.from(' , \r\n ')
    })
    await expect(page.getByText('文件中没有可用的序列号，请检查文件内容后重试')).toBeVisible()
    await expect(lineDialog.getByText('已录入 0 个')).toBeVisible()
    await fileInput.setInputFiles({
      name: 'serials.txt',
      mimeType: 'text/plain',
      buffer: Buffer.from('SERIAL-001\nSERIAL-002')
    })
    await expect(lineDialog.getByText('已录入 2 个')).toBeVisible()
    await lineDialog.getByRole('button', { name: '查看序列号' }).click()
    await expect(serialDialog.getByText('SERIAL-001')).toBeVisible()
    await expect(serialDialog.getByText('SERIAL-002')).toBeVisible()
    await expect(serialDialog.locator('.art-empty-state')).toHaveCount(0)
    await page.screenshot({
      path: `.artifacts/wms-${kind}-serials-filled-${testInfo.project.name}.png`,
      animations: 'disabled'
    })
  })
}
