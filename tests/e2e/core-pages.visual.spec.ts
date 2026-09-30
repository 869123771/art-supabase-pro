import { expect, test, type Locator, type Page } from '@playwright/test'

interface VisualPage {
  name: string
  path: string
  root: string
  captureLower?: boolean
}

const visualPages: VisualPage[] = [
  {
    name: 'dashboard-console',
    path: '/dashboard/console',
    root: '.operations-dashboard'
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
  },
  {
    name: 'ai-project-planner',
    path: '/system/ai-project-planner',
    root: '.ai-planner'
  },
  {
    name: 'website-config',
    path: '/system/website-config',
    root: '.website-config-page',
    captureLower: true
  }
]

const VISUAL_TEST_TIME = new Date('2026-08-10T10:26:52.000Z')

async function waitForPageReady(page: Page, rootSelector: string): Promise<Locator> {
  const root = page.locator(rootSelector).first()
  await expect(root).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 60_000 })
  await page.waitForTimeout(500)
  return root
}

async function dismissSettingGuide(page: Page): Promise<void> {
  const guide = page.locator('.setting-guide')
  const becameVisible = await guide
    .waitFor({ state: 'visible', timeout: 2_000 })
    .then(() => true)
    .catch(() => false)

  if (becameVisible) {
    await guide.getByRole('button', { name: '知道了' }).click()
    await expect(guide).toBeHidden()
  }
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

async function scrollMainContentToBottom(page: Page): Promise<void> {
  await page.evaluate(() => {
    const scrollContainer =
      document.querySelector<HTMLElement>(
        '#app-main > .app-main__scrollbar > .app-main__scroll-wrap'
      ) ?? document.scrollingElement
    scrollContainer?.scrollTo({ top: scrollContainer.scrollHeight, behavior: 'auto' })
  })
  await page.waitForTimeout(200)
}

async function applyVisualMode(page: Page, projectName: string): Promise<void> {
  await page.evaluate(
    ({ dark, boxMode }) => {
      document.documentElement.classList.toggle('dark', dark)
      document.documentElement.dataset.boxMode = boxMode
    },
    {
      dark: projectName.includes('dark'),
      boxMode: projectName.includes('shadow') ? 'shadow-mode' : 'border-mode'
    }
  )
}

for (const visualPage of visualPages) {
  test(`${visualPage.name} 布局稳定`, async ({ page }, testInfo) => {
    test.setTimeout(120_000)
    const pageErrors: string[] = []
    page.on('pageerror', (error) => pageErrors.push(error.message))

    await page.clock.setFixedTime(VISUAL_TEST_TIME)
    await page.goto(`/#${visualPage.path}`, { waitUntil: 'domcontentloaded' })
    await expect(page).not.toHaveURL(/#\/auth\/login/)

    await waitForPageReady(page, visualPage.root)
    await dismissSettingGuide(page)
    await applyVisualMode(page, testInfo.project.name)
    await expectNoHorizontalOverflow(page)
    await resetScrollPositions(page)

    await expect(page).toHaveScreenshot(`${visualPage.name}.png`)

    if (visualPage.captureLower) {
      await scrollMainContentToBottom(page)
      await expect(page).toHaveScreenshot(`${visualPage.name}-lower.png`)
    }
    expect(pageErrors, `页面出现未捕获错误：\n${pageErrors.join('\n')}`).toEqual([])
  })
}
