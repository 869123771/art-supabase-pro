import { expect, test, type Page } from '@playwright/test'

async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const viewport = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }))
  expect(viewport.scrollWidth).toBeLessThanOrEqual(viewport.clientWidth + 1)
}

test('菜单服务故障后，会话有效时重试进入系统主页', async ({ page }) => {
  test.setTimeout(120_000)
  let shouldFailMenuRequest = true

  await page.route('**/rest/v1/rpc/get_menus_for_current_application', async (route) => {
    if (!shouldFailMenuRequest) {
      await route.continue()
      return
    }

    await route.fulfill({
      status: 503,
      contentType: 'application/json',
      body: JSON.stringify({
        code: 'PGRST503',
        message: 'Injected menu service failure'
      })
    })
  })

  await page.goto('/#/dashboard/console', { waitUntil: 'domcontentloaded' })

  await expect(page.getByRole('heading', { name: '服务暂时开小差' })).toBeVisible({
    timeout: 30_000
  })
  await expect(page).toHaveURL(/#\/500\?redirect=\/dashboard\/console/)
  await expect(page.getByRole('button', { name: '重试进入系统' })).toBeVisible()
  await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0)
  await expectNoHorizontalOverflow(page)

  shouldFailMenuRequest = false
  await page.getByRole('button', { name: '重试进入系统' }).click()

  await expect(page).toHaveURL(/#\/dashboard\/console/, { timeout: 60_000 })
  await expect(page.locator('.operations-dashboard')).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 60_000 })
})

test('会话失效时重试会退出并返回登录页', async ({ context, page }) => {
  await context.clearCookies()
  await page.addInitScript(() => window.localStorage.clear())
  await page.goto('/#/500?redirect=/dashboard/console', { waitUntil: 'domcontentloaded' })

  await page.getByRole('button', { name: '重试进入系统', exact: true }).click()

  await expect(page).toHaveURL(/#\/auth\/login\?redirect=\//)
  await expect(page.locator('.auth-right-wrap .form')).toBeVisible()
  await expectNoHorizontalOverflow(page)
})

test('用户可从服务异常页主动退出并返回登录页', async ({ page }) => {
  await page.goto('/#/500?redirect=/', { waitUntil: 'domcontentloaded' })

  await page.getByRole('button', { name: '返回登录', exact: true }).click()

  await expect(page).toHaveURL(/#\/auth\/login\?redirect=\//)
  await expect(page.locator('.auth-right-wrap .form')).toBeVisible()
  await expectNoHorizontalOverflow(page)
})
