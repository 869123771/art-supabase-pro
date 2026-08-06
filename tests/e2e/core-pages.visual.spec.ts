import { expect, test, type Locator, type Page } from '@playwright/test'

interface VisualPage {
  name: string
  path: string
  root: string
}

const visualPages: VisualPage[] = [
  {
    name: 'dashboard-console',
    path: '/dashboard/console',
    root: '.operations-dashboard'
  },
  {
    name: 'in-transit-monitor',
    path: '/tms-transportation/in-transit-monitor',
    root: '.transit-screen__viewport'
  },
  {
    name: 'invoice-management',
    path: '/tms-transportation/finance-center/invoice-management',
    root: '.art-table-query'
  },
  {
    name: 'supabase-ai-assistant',
    path: '/data-center/supabase-ai-assistant',
    root: '.project-assistant'
  },
  {
    name: 'table-query-widget',
    path: '/widgets/table-query',
    root: '.table-query-widget'
  }
]

async function waitForPageReady(page: Page, rootSelector: string): Promise<Locator> {
  const root = page.locator(rootSelector).first()
  await expect(root).toBeVisible({ timeout: 30_000 })
  await page
    .locator('.el-loading-mask')
    .waitFor({ state: 'hidden', timeout: 20_000 })
    .catch(() => {})
  await page.waitForTimeout(500)
  return root
}

async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const overflow = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }))
  expect(
    overflow.scrollWidth,
    `页面产生横向溢出：scrollWidth=${overflow.scrollWidth}, clientWidth=${overflow.clientWidth}`
  ).toBeLessThanOrEqual(overflow.clientWidth + 1)
}

async function resetScrollPositions(page: Page): Promise<void> {
  await page.evaluate(() => {
    window.scrollTo(0, 0)
    for (const element of document.querySelectorAll<HTMLElement>('*')) {
      if (element.scrollTop) element.scrollTop = 0
      if (element.scrollLeft) element.scrollLeft = 0
    }
  })
  await page.waitForTimeout(100)
}

test('核心页面布局稳定', async ({ page }) => {
  test.setTimeout(180_000)
  const pageErrors: string[] = []
  page.on('pageerror', (error) => pageErrors.push(error.message))

  await page.goto('/#/dashboard/console', { waitUntil: 'domcontentloaded' })
  await expect(page).not.toHaveURL(/#\/auth\/login/)

  for (const visualPage of visualPages) {
    await test.step(visualPage.name, async () => {
      pageErrors.length = 0
      if (!page.url().endsWith(`#${visualPage.path}`)) {
        await page.evaluate((routePath) => {
          window.location.hash = routePath
        }, visualPage.path)
      }
      await expect(page).toHaveURL(new RegExp(`#${visualPage.path.replaceAll('/', '\\/')}$`))

      const root = await waitForPageReady(page, visualPage.root)
      await expectNoHorizontalOverflow(page)
      await resetScrollPositions(page)

      await expect(root).toHaveScreenshot(`${visualPage.name}.png`)

      expect(pageErrors, `页面出现未捕获错误：\n${pageErrors.join('\n')}`).toEqual([])
    })
  }
})
