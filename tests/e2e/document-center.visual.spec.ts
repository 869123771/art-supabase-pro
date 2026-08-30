import { mkdir } from 'node:fs/promises'
import path from 'node:path'
import { expect, test } from '@playwright/test'

type MockMenu = {
  id: string
  parentId: string | null
  name: string
  path: string
  component: string
  type: 'button' | 'folder' | 'menu'
  meta: Record<string, unknown>
  sort: number
  children?: MockMenu[]
}

const pageMenuId = '164cfd80-a0dd-4e0b-b9f8-365bfdeae6a0'
const buttonNames = [
  'View',
  'Add',
  'Upload',
  'Edit',
  'Delete',
  'Export',
  'Follow',
  'Share',
  'CategoryAdd',
  'CategoryEdit',
  'CategoryDelete'
]

const buttons: MockMenu[] = buttonNames.map((name, index) => ({
  id: `10000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
  parentId: pageMenuId,
  name: `SmisAllDocuments:${name}`,
  path: '',
  component: '',
  type: 'button',
  meta: { is_enable: true, is_hide: true, roles: [], title: name },
  sort: index + 1
}))

const pageMenu: MockMenu = {
  id: pageMenuId,
  parentId: 'eccbb9a9-8543-4299-86af-36a3b1dcc077',
  name: 'SmisAllDocuments',
  path: 'all-documents',
  component: '/smis/safety-production/document-center/all-documents',
  type: 'menu',
  meta: { icon: '', is_enable: true, is_hide: false, roles: [], title: '全部文档' },
  sort: 1,
  children: buttons
}

const documentCenterMenu: MockMenu = {
  id: 'eccbb9a9-8543-4299-86af-36a3b1dcc077',
  parentId: 'a1530000-0000-4000-8000-000000000004',
  name: 'SmisDocumentCenter',
  path: 'document-center',
  component: '',
  type: 'folder',
  meta: {
    icon: 'ri:folder-shield-2-line',
    is_enable: true,
    is_hide: false,
    roles: [],
    title: '文档中心'
  },
  sort: 6,
  children: [pageMenu]
}

const safetyProductionMenu: MockMenu = {
  id: 'a1530000-0000-4000-8000-000000000004',
  parentId: 'a1530000-0000-4000-8000-000000000001',
  name: 'SmisSafetyProduction',
  path: 'safety-production',
  component: '',
  type: 'folder',
  meta: {
    icon: 'ri:shield-star-line',
    is_enable: true,
    is_hide: false,
    roles: [],
    title: '安全生产'
  },
  sort: 3,
  children: [documentCenterMenu]
}

const rootMenu: MockMenu = {
  id: 'a1530000-0000-4000-8000-000000000001',
  parentId: null,
  name: 'SmisSafetyManagement',
  path: '/smis',
  component: '/index/index',
  type: 'folder',
  meta: {
    icon: 'ri:shield-check-line',
    is_enable: true,
    is_hide: false,
    keep_alive: true,
    roles: [],
    title: 'SMIS安全管理'
  },
  sort: 14,
  children: [safetyProductionMenu]
}

const flatMenus = [rootMenu, safetyProductionMenu, documentCenterMenu, pageMenu, ...buttons].map(
  (menu) => ({
    id: menu.id,
    parentId: menu.parentId,
    name: menu.name,
    path: menu.path,
    component: menu.component,
    type: menu.type,
    meta: menu.meta,
    sort: menu.sort
  })
)

const categories = [
  {
    id: '20000000-0000-4000-8000-000000000001',
    parentId: null,
    categoryName: '企业制度',
    sort: 10,
    status: 'enabled',
    description: '企业级受控文件',
    documentCount: 3,
    createTime: '2026-08-01T09:00:00+08:00',
    updateTime: '2026-08-30T09:00:00+08:00'
  },
  {
    id: '20000000-0000-4000-8000-000000000002',
    parentId: '20000000-0000-4000-8000-000000000001',
    categoryName: '人事制度',
    sort: 10,
    status: 'enabled',
    description: '人事管理制度',
    documentCount: 2,
    createTime: '2026-08-01T09:00:00+08:00',
    updateTime: '2026-08-30T09:00:00+08:00'
  },
  {
    id: '20000000-0000-4000-8000-000000000003',
    parentId: null,
    categoryName: '检验标准',
    sort: 20,
    status: 'enabled',
    description: '质量检验文件',
    documentCount: 1,
    createTime: '2026-08-01T09:00:00+08:00',
    updateTime: '2026-08-30T09:00:00+08:00'
  }
]

const documents = [
  {
    id: '30000000-0000-4000-8000-000000000001',
    categoryId: categories[1].id,
    categoryName: '人事制度',
    categoryPath: '企业制度 / 人事制度',
    title: '员工入职与转正管理制度',
    status: 'published',
    summary: '规范员工入职、试用期评估与转正审批流程。',
    creatorUserId: '40000000-0000-4000-8000-000000000001',
    creatorName: '系统管理员',
    versionNo: 2,
    latestVersionNo: 3,
    fileName: '员工入职与转正管理制度.pdf',
    fileUrl: 'https://example.invalid/employee-onboarding.pdf',
    fileType: 'pdf',
    fileSize: 1864320,
    effectiveDate: '2026-07-01',
    latestEffectiveDate: '2026-09-10',
    scheduledEffectiveDate: '2026-09-10',
    implementationState: 'scheduled',
    isFollowing: true,
    sharedByMeCount: 2,
    sharedToMe: false,
    createTime: '2026-06-20T10:00:00+08:00',
    updateTime: '2026-08-30T09:30:00+08:00'
  },
  {
    id: '30000000-0000-4000-8000-000000000002',
    categoryId: categories[0].id,
    categoryName: '企业制度',
    categoryPath: '企业制度',
    title: '收入证明办理指南',
    status: 'published',
    summary: '收入证明开具条件、材料清单与审批时限。',
    creatorUserId: '40000000-0000-4000-8000-000000000001',
    creatorName: '系统管理员',
    versionNo: 1,
    latestVersionNo: 1,
    fileName: '收入证明办理指南.docx',
    fileUrl: 'https://example.invalid/income-proof.docx',
    fileType: 'docx',
    fileSize: 428032,
    effectiveDate: '2026-08-01',
    latestEffectiveDate: '2026-08-01',
    scheduledEffectiveDate: null,
    implementationState: 'effective',
    isFollowing: false,
    sharedByMeCount: 0,
    sharedToMe: true,
    createTime: '2026-07-20T10:00:00+08:00',
    updateTime: '2026-08-25T16:20:00+08:00'
  },
  {
    id: '30000000-0000-4000-8000-000000000003',
    categoryId: categories[2].id,
    categoryName: '检验标准',
    categoryPath: '检验标准',
    title: '原材料进场检验规范',
    status: 'draft',
    summary: '待补充抽样频次与复验规则。',
    creatorUserId: '40000000-0000-4000-8000-000000000001',
    creatorName: '质量专员',
    versionNo: null,
    latestVersionNo: null,
    fileName: null,
    fileUrl: null,
    fileType: null,
    fileSize: null,
    effectiveDate: null,
    latestEffectiveDate: null,
    scheduledEffectiveDate: null,
    implementationState: 'no_file',
    isFollowing: false,
    sharedByMeCount: 0,
    sharedToMe: false,
    createTime: '2026-08-28T10:00:00+08:00',
    updateTime: '2026-08-29T11:15:00+08:00'
  }
]

const corsHeaders = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, apikey, content-type, x-client-info',
  'access-control-allow-methods': 'POST, OPTIONS'
}

test.beforeEach(async ({ page }) => {
  await page.route('**/rest/v1/rpc/get_menus_for_current_application', (route) =>
    route.fulfill({
      contentType: 'application/json',
      headers: corsHeaders,
      body: JSON.stringify({ flat: flatMenus, tree: [rootMenu] })
    })
  )
  await page.route('**/rest/v1/rpc/smis_list_document_categories_secure', (route) =>
    route.fulfill({
      contentType: 'application/json',
      headers: corsHeaders,
      body: JSON.stringify(categories)
    })
  )
  await page.route('**/rest/v1/rpc/smis_list_documents_secure', (route) =>
    route.fulfill({
      contentType: 'application/json',
      headers: corsHeaders,
      body: JSON.stringify({
        records: documents,
        total: documents.length,
        overview: { total: documents.length, published: 2, draft: 1, scheduled: 1 }
      })
    })
  )
})

test('文档中心三视图在桌面和窄屏下无页面级溢出', async ({ page }, testInfo) => {
  test.setTimeout(120_000)
  await page.goto('/#/smis/safety-production/document-center/all-documents', {
    waitUntil: 'domcontentloaded'
  })
  await expect(page.locator('.document-center-page')).toBeVisible({ timeout: 45_000 })
  await expect(page.getByRole('heading', { name: '全部文档' })).toBeVisible()
  await expect(
    page.getByRole('button', { name: '员工入职与转正管理制度', exact: true })
  ).toBeVisible()

  const outputDir = path.join(process.cwd(), '.artifacts', 'ui-quality', 'document-center-e2e')
  await mkdir(outputDir, { recursive: true })
  const viewModes = [
    { name: '文件夹视图', value: 'folder' },
    { name: '列表视图', value: 'list' },
    { name: '树结构视图', value: 'tree' }
  ]
  for (const viewMode of viewModes) {
    const viewName = viewMode.name
    await page.getByRole('button', { name: viewName }).click()
    await expect(page.locator('.document-center-page__content')).toHaveClass(
      new RegExp(`is-${viewMode.value}`)
    )
    await page.mouse.move(0, 0)
    await page.waitForTimeout(250)
    await page.screenshot({
      path: path.join(outputDir, `${testInfo.project.name}-${viewMode.value}.png`),
      fullPage: true,
      animations: 'disabled'
    })
  }

  const overflow = await page.evaluate(() => ({
    document: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    body: document.body.scrollWidth - document.body.clientWidth
  }))
  expect(overflow.document).toBeLessThanOrEqual(1)
  expect(overflow.body).toBeLessThanOrEqual(1)
})
