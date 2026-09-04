import { expect, test, type ConsoleMessage, type Page } from '@playwright/test'

interface TestMenuNode {
  id: string
  parentId: string | null
  name: string
  path: string
  component: string
  type: string
  sort: number
  meta: Record<string, unknown>
  children?: TestMenuNode[]
}

const menuMeta = (title: string, icon: string) => ({
  title,
  icon,
  roles: ['R_SUPER', 'R_ADMIN'],
  is_hide: false,
  is_enable: true,
  keep_alive: true
})

const createAppMenu = (
  code: 'mdm' | 'wms' | 'mes',
  title: string,
  icon: string,
  component: string
): TestMenuNode => {
  const rootId = `test-${code}-root`
  return {
    id: rootId,
    parentId: null,
    name: `${code.toUpperCase()}Root`,
    path: `/${code}`,
    component: '/index/index',
    type: 'folder',
    sort: 1,
    meta: menuMeta(title, icon),
    children: [
      {
        id: `test-${code}-workbench`,
        parentId: rootId,
        name: `${code.toUpperCase()}Workbench`,
        path: 'workbench',
        component,
        type: 'menu',
        sort: 1,
        meta: menuMeta(code === 'wms' ? '仓储工作台' : '制造工作台', 'ri:dashboard-3-line'),
        children: []
      }
    ]
  }
}

const mdmMenu: TestMenuNode = {
  ...createAppMenu('mdm', 'MDM主数据', 'ri:database-2-line', '/mdm/workbench'),
  children: [
    {
      id: 'test-mdm-workbench',
      parentId: 'test-mdm-root',
      name: 'MDMWorkbench',
      path: 'workbench',
      component: '/mdm/workbench',
      type: 'menu',
      sort: 0,
      meta: menuMeta('治理总览', 'ri:dashboard-3-line'),
      children: []
    },
    {
      id: 'test-mdm-organization',
      parentId: 'test-mdm-root',
      name: 'MDMOrganization',
      path: 'organization',
      component: '',
      type: 'folder',
      sort: 1,
      meta: menuMeta('组织与人员', 'ri:organization-chart'),
      children: [
        {
          id: 'test-mdm-organization-directory',
          parentId: 'test-mdm-organization',
          name: 'MDMOrganizationDirectory',
          path: 'organization-directory',
          component: '/mdm/catalog',
          type: 'menu',
          sort: 1,
          meta: menuMeta('组织机构主数据', 'ri:organization-chart'),
          children: []
        }
      ]
    }
  ]
}

const testMenus: Record<'mdm' | 'wms' | 'mes', TestMenuNode> = {
  mdm: mdmMenu,
  wms: createAppMenu('wms', 'WMS仓储管理', 'ri:warehouse-line', '/wms/workbench'),
  mes: createAppMenu('mes', 'MES制造执行', 'ri:factory-line', '/mes/workbench')
}

function flattenMenu(node: TestMenuNode): TestMenuNode[] {
  return [{ ...node, children: undefined }, ...(node.children ?? []).flatMap(flattenMenu)]
}

async function installApplicationMenuMocks(page: Page): Promise<void> {
  await page.route('**/rest/v1/rpc/get_accessible_applications', async (route) => {
    await route.fulfill({
      json: [
        {
          code: 'platform',
          name: 'Art Supabase Pro',
          description: '企业数字化平台',
          baseUrl: '/',
          sort: 1
        },
        {
          code: 'mdm',
          name: 'Art Supabase MDM',
          description: '主数据治理',
          baseUrl: '/mdm/',
          sort: 15
        },
        {
          code: 'wms',
          name: 'Art Supabase WMS',
          description: '仓储管理',
          baseUrl: '/wms/',
          sort: 55
        },
        {
          code: 'mes',
          name: 'Art Supabase MES',
          description: '制造执行',
          baseUrl: '/mes/',
          sort: 60
        }
      ]
    })
  })

  await page.route('**/rest/v1/rpc/get_menus_for_current_application', async (route) => {
    const payload = route.request().postDataJSON() as { p_app_code?: string }
    const code = payload.p_app_code as keyof typeof testMenus
    const menu = testMenus[code]
    if (!menu) {
      await route.continue()
      return
    }
    await route.fulfill({ json: { flat: flattenMenu(menu), tree: [menu] } })
  })
}

async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const overflow = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }))
  expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.clientWidth + 1)
}

async function openWorkspace(page: Page, path: string, heading: string): Promise<void> {
  const errors: string[] = []
  const handleConsole = (message: ConsoleMessage) => {
    if (message.type() === 'error') errors.push(message.text())
  }
  page.on('console', handleConsole)

  try {
    await page.goto(path, { waitUntil: 'domcontentloaded' })
    await expect(page.getByRole('heading', { name: heading, exact: true })).toBeVisible({
      timeout: 60_000
    })
    await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 60_000 })
    await expect(page.locator('.el-skeleton')).toHaveCount(0, { timeout: 60_000 })
    await expectNoHorizontalOverflow(page)
    expect(errors).toEqual([])
  } finally {
    page.off('console', handleConsole)
  }
}

test.describe('MDM, WMS and MES application scaffolds', () => {
  test.describe.configure({ timeout: 120_000 })

  test('opens the MDM governance workspace and catalog', async ({ page }, testInfo) => {
    await installApplicationMenuMocks(page)
    await openWorkspace(page, '/#/mdm/workbench', '主数据治理工作台')
    await page.screenshot({ path: testInfo.outputPath('mdm-workbench.png'), fullPage: true })

    await openWorkspace(page, '/#/mdm/organization/organization-directory', '组织机构主数据')
    await expect(page.getByText('权威来源约定', { exact: true })).toBeVisible()
    await expect(page.getByText('当前结果', { exact: true })).toBeVisible()
    const keywordInput = page.getByPlaceholder('组织编码或名称')
    await keywordInput.fill('ROOT')
    await keywordInput.press('Enter')
    await expect(page.getByText('ROOT', { exact: true }).first()).toBeVisible()
    await expect(page.getByRole('button', { name: '查看详情' }).first()).toBeVisible()
    await page.getByRole('button', { name: '查看详情' }).first().click()
    await expect(page.getByText('主数据详情', { exact: true })).toBeVisible()
    await expect(page.getByText('治理与来源', { exact: true })).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await page.screenshot({ path: testInfo.outputPath('mdm-catalog-detail.png'), fullPage: true })
  })

  test('opens the WMS workspace', async ({ page }, testInfo) => {
    await installApplicationMenuMocks(page)
    await openWorkspace(page, '/#/wms/workbench', '仓储运营工作台')
    await expect(page.getByText('架构准备阶段', { exact: true })).toBeVisible()
    await page.screenshot({ path: testInfo.outputPath('wms-workbench.png'), fullPage: true })
  })

  test('opens the MES workspace', async ({ page }, testInfo) => {
    await installApplicationMenuMocks(page)
    await openWorkspace(page, '/#/mes/workbench', '制造执行工作台')
    await expect(page.getByText('架构准备阶段', { exact: true })).toBeVisible()
    await page.screenshot({ path: testInfo.outputPath('mes-workbench.png'), fullPage: true })
  })
})
