import fs from 'node:fs'
import { expect, test, type Request } from '@playwright/test'

interface RequestTiming {
  method: string
  url: string
  startedAt: number
  finishedAt?: number
  failure?: string | null
}

function readDemoCredentials(): { email: string; password: string } {
  const loginSource = fs.readFileSync('src/views/auth/login/index.vue', 'utf8')
  const email = process.env.E2E_EMAIL || loginSource.match(/identifier:\s*'([^']+)'/)?.[1]
  const password = process.env.E2E_PASSWORD || loginSource.match(/password:\s*'([^']+)'/)?.[1]

  if (!email || !password) {
    throw new Error('请通过 E2E_EMAIL 和 E2E_PASSWORD 提供首次登录回归账号')
  }
  return { email, password }
}

test.use({ storageState: { cookies: [], origins: [] } })

test('全新浏览器首次登录后可以立即切换到另一个菜单', async ({ page }) => {
  test.setTimeout(120_000)
  const requestTimings = new Map<Request, RequestTiming>()
  const pageErrors: string[] = []
  const hostedApplicationRequests: string[] = []

  page.on('pageerror', (error) => pageErrors.push(error.message))
  page.on('request', (request) => {
    if (/bootstrapHostedApplications(?:-|\.ts)/.test(new URL(request.url()).pathname)) {
      hostedApplicationRequests.push(request.url())
    }
    if (!request.url().includes('supabase.co')) return
    requestTimings.set(request, {
      method: request.method(),
      url: request.url(),
      startedAt: Date.now()
    })
  })
  page.on('requestfinished', (request) => {
    const timing = requestTimings.get(request)
    if (timing) timing.finishedAt = Date.now()
  })
  page.on('requestfailed', (request) => {
    const timing = requestTimings.get(request)
    if (!timing) return
    timing.finishedAt = Date.now()
    timing.failure = request.failure()?.errorText
  })

  const credentials = readDemoCredentials()
  await page.goto('/#/auth/login', { waitUntil: 'domcontentloaded' })
  await expect(page.getByRole('heading', { name: '欢迎使用', exact: true })).toBeVisible({
    timeout: 30_000
  })
  expect(hostedApplicationRequests).toEqual([])
  await page.getByRole('textbox', { name: '邮箱或手机号' }).fill(credentials.email)
  await page.locator('input[name="password"]').fill(credentials.password)

  const loginStartedAt = Date.now()
  await page.getByRole('button', { name: '登录', exact: true }).click()
  await expect(page).toHaveURL(/#\/dashboard\/console$/, { timeout: 90_000 })
  await expect(page.getByRole('heading', { name: '今日运营概览' })).toBeVisible({
    timeout: 90_000
  })
  const dashboardReadyAt = Date.now()
  expect(hostedApplicationRequests.length).toBeGreaterThan(0)

  await page.getByRole('menuitem', { name: '系统管理', exact: true }).click()
  const targetMenu = page.locator('.el-menu-item').filter({ hasText: '电子围栏配置' }).first()
  await expect(targetMenu).toBeVisible({ timeout: 30_000 })
  const navigationStartedAt = Date.now()
  await targetMenu.click()
  await expect(page).toHaveURL(/#\/system\/geofence-config$/, { timeout: 90_000 })
  await expect(page.getByRole('heading', { name: '电子围栏配置', exact: true })).toBeVisible({
    timeout: 90_000
  })
  const targetReadyAt = Date.now()

  const slowRequests = [...requestTimings.values()]
    .filter((timing) => timing.finishedAt)
    .map((timing) => ({
      method: timing.method,
      pathname: new URL(timing.url).pathname,
      durationMs: timing.finishedAt! - timing.startedAt,
      failure: timing.failure
    }))
    .filter((timing) => timing.durationMs >= 500)
    .sort((left, right) => right.durationMs - left.durationMs)

  console.info(
    JSON.stringify(
      {
        loginToDashboardMs: dashboardReadyAt - loginStartedAt,
        firstMenuNavigationMs: targetReadyAt - navigationStartedAt,
        slowRequests
      },
      null,
      2
    )
  )

  expect(pageErrors).toEqual([])
})
