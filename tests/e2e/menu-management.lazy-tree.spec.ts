import { expect, test, type Page, type Request } from '@playwright/test'

interface MenuRpcPayload {
  p_parent_id: string | null
  p_root_only: boolean
}

interface MenuRpcRow {
  id: string
  parent_id: string | null
}

const isMenuRpcRequest = (request: Request): boolean =>
  request.method() === 'POST' && request.url().includes('/rest/v1/rpc/list_menu_management_nodes')

const readMenuRpcPayload = (request: Request): MenuRpcPayload =>
  request.postDataJSON() as MenuRpcPayload

async function readMenuRows(request: Request): Promise<MenuRpcRow[]> {
  const response = await request.response()
  expect(response, '菜单 RPC 应返回网络响应').not.toBeNull()
  expect(response?.ok(), `菜单 RPC 请求失败：${response?.status()}`).toBe(true)
  return (await response?.json()) as MenuRpcRow[]
}

async function waitForMenuTable(page: Page, rootCount: number): Promise<void> {
  await expect(page.getByRole('heading', { name: '菜单管理', exact: true })).toBeVisible({
    timeout: 60_000
  })
  await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 60_000 })
  await expect(page.locator('.el-table__body-wrapper tbody tr')).toHaveCount(rootCount, {
    timeout: 60_000
  })
}

test('菜单管理首层与展开请求保持精简且层级正确', async ({ page }, testInfo) => {
  test.setTimeout(120_000)
  const menuRequests: Request[] = []
  const legacyChildQueries: string[] = []

  page.on('request', (request) => {
    if (isMenuRpcRequest(request)) menuRequests.push(request)
    if (request.url().includes('/rest/v1/sys_menu') && request.url().includes('parent_id=in.')) {
      legacyChildQueries.push(request.url())
    }
  })

  const rootRequestPromise = page.waitForRequest(
    (request) => isMenuRpcRequest(request) && readMenuRpcPayload(request).p_root_only === true
  )
  await page.goto('/#/system/menu', { waitUntil: 'domcontentloaded' })
  await expect(page).not.toHaveURL(/#\/auth\/login/)
  const rootRequest = await rootRequestPromise
  const rootRows = await readMenuRows(rootRequest)

  expect(readMenuRpcPayload(rootRequest)).toMatchObject({
    p_parent_id: null,
    p_root_only: true
  })
  expect(rootRows.length).toBeGreaterThan(0)
  expect(rootRows.every((row) => row.parent_id === null)).toBe(true)
  await waitForMenuTable(page, rootRows.length)

  const firstRoot = rootRows[0]
  const childRequestPromise = page.waitForRequest((request) => {
    if (!isMenuRpcRequest(request)) return false
    const payload = readMenuRpcPayload(request)
    return payload.p_parent_id === firstRoot.id && payload.p_root_only === false
  })

  await page
    .locator('.el-table__body-wrapper tbody tr')
    .first()
    .locator('.el-table__expand-icon')
    .click()
  const childRequest = await childRequestPromise
  const childRows = await readMenuRows(childRequest)

  expect(childRows.length).toBeGreaterThan(0)
  expect(childRows.every((row) => row.parent_id === firstRoot.id)).toBe(true)
  await expect(page.locator('.el-table__body-wrapper tbody tr')).toHaveCount(
    rootRows.length + childRows.length
  )
  expect(menuRequests).toHaveLength(2)
  expect(legacyChildQueries).toEqual([])

  // Exercise the real ancestor-query consumer without persisting any menu changes.
  const rows = page.locator('.el-table__body-wrapper tbody tr')
  const parentTitle = await rows.first().locator('.menu-identity-cell__heading strong').innerText()
  const childTitle = await rows.nth(1).locator('.menu-identity-cell__heading strong').innerText()
  await rows.nth(1).getByRole('button', { name: '查看详情', exact: true }).click()
  const breadcrumb = page.getByRole('navigation', { name: '菜单层级路径' })
  await expect(breadcrumb).toBeVisible()
  await expect(breadcrumb.locator(':scope > span')).toHaveText([parentTitle, childTitle])
  await expect(
    page.locator('.menu-detail__metrics article').filter({ hasText: '层级深度' }).locator('strong')
  ).toHaveText('2')
  await breadcrumb.screenshot({ path: testInfo.outputPath('menu-ancestor-path.png') })
  await page.keyboard.press('Escape')
  await expect(breadcrumb).toBeHidden()
})
