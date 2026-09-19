import { expect, test, type Page } from '@playwright/test'

interface AuthFieldExpectation {
  name: string
  autocomplete: string
}

interface AuthPageExpectation {
  path: string
  fields: AuthFieldExpectation[]
  mayBeDisabled?: boolean
}

const authPages: AuthPageExpectation[] = [
  {
    path: '/auth/register',
    mayBeDisabled: true,
    fields: [
      { name: 'email', autocomplete: 'email' },
      { name: 'password', autocomplete: 'new-password' },
      { name: 'confirmPassword', autocomplete: 'new-password' }
    ]
  },
  {
    path: '/auth/forget-password',
    fields: [{ name: 'email', autocomplete: 'email' }]
  },
  {
    path: '/auth/reset-password',
    fields: [
      { name: 'password', autocomplete: 'new-password' },
      { name: 'confirmPassword', autocomplete: 'new-password' }
    ]
  }
]

async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const viewport = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }))
  expect(viewport.scrollWidth).toBeLessThanOrEqual(viewport.clientWidth + 1)
}

for (const authPage of authPages) {
  test(`${authPage.path} exposes semantic form fields`, async ({ page }) => {
    const pageErrors: string[] = []
    page.on('pageerror', (error) => pageErrors.push(error.message))

    await page.goto(`/#${authPage.path}`, { waitUntil: 'domcontentloaded' })
    if (authPage.mayBeDisabled && /#\/403$/.test(page.url())) {
      await expect(page.getByRole('heading', { name: '当前账号无法访问' })).toBeVisible()
      return
    }
    await expect(page.locator('.auth-right-wrap .form')).toBeVisible()

    for (const field of authPage.fields) {
      const input = page.locator(`input[name="${field.name}"]`)
      await expect(input).toHaveCount(1)
      await expect(input).toHaveAttribute('autocomplete', field.autocomplete)
      await expect(input).toHaveAttribute('aria-label', /\S+/)
    }

    await expectNoHorizontalOverflow(page)
    expect(pageErrors).toEqual([])
  })
}

test('login support links have usable hit areas', async ({ page }, testInfo) => {
  await page.goto('/#/auth/login', { waitUntil: 'domcontentloaded' })
  await expect(page.locator('.auth-right-wrap .form')).toBeVisible()

  for (const name of ['忘记密码', '注册']) {
    const link = page.getByRole('link', { name, exact: true })
    await expect(link).toBeVisible()
    const bounds = await link.boundingBox()
    const minimumSize = testInfo.project.name.includes('mobile') ? 44 : 24
    expect(bounds?.width).toBeGreaterThanOrEqual(minimumSize)
    expect(bounds?.height).toBeGreaterThanOrEqual(minimumSize)
  }

  await expectNoHorizontalOverflow(page)
})

test('desktop Feishu login switches the card to an inline QR and back', async ({
  page
}, testInfo) => {
  test.skip(testInfo.project.name.includes('mobile'))
  await page.route('**/functions/v1/oauth-provider-bridge/feishu/qr-prepare', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        goto: 'https://passport.feishu.cn/suite/passport/oauth/authorize?client_id=cli_test&redirect_uri=https%3A%2F%2Fexample.com%2Fcallback&response_type=code&state=test-state'
      })
    })
  })
  await page.route('**/LarkSSOSDKWebQRCode-1.0.3.js', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/javascript',
      body: `window.QRLogin = ({ id }) => {
        const iframe = document.createElement('iframe');
        iframe.src = 'about:blank';
        document.getElementById(id).appendChild(iframe);
        return { matchOrigin: () => true, matchData: () => true };
      };`
    })
  })
  await page.goto('/#/auth/login', { waitUntil: 'domcontentloaded' })
  const feishuButton = page.getByRole('button', { name: '使用飞书登录' })
  const channelReady = await feishuButton
    .waitFor({ state: 'visible', timeout: 10_000 })
    .then(() => true)
    .catch(() => false)
  test.skip(!channelReady, '飞书渠道尚未在网站配置中启用')

  await feishuButton.click()
  await expect(page.getByRole('heading', { name: '飞书扫码登录' })).toBeVisible()
  await expect(page.locator('.feishu-qr__code iframe')).toBeVisible()
  await expect(page.getByText('用飞书 App 扫一扫，并在手机上确认')).toBeVisible()
  await expect(page.getByRole('button', { name: '飞书网页授权登录' })).toBeVisible()
  await expectNoHorizontalOverflow(page)

  await page.getByRole('button', { name: '返回账号密码登录' }).click()
  await expect(page.locator('input[name="username"]')).toBeVisible()
})

test('anonymous login does not download hosted business page mappings', async ({ page }) => {
  const hostedRequests: string[] = []
  page.on('request', (request) => {
    if (/bootstrapHostedApplications(?:-|\.ts)/.test(new URL(request.url()).pathname)) {
      hostedRequests.push(request.url())
    }
  })

  await page.goto('/#/auth/login', { waitUntil: 'domcontentloaded' })
  await expect(page.locator('.auth-right-wrap .form')).toBeVisible()

  expect(hostedRequests).toEqual([])
})

test('short phone login keeps its header and final controls reachable', async ({
  page
}, testInfo) => {
  test.skip(!testInfo.project.name.includes('mobile'))
  await page.setViewportSize({ width: 320, height: 700 })
  await page.goto('/#/auth/login', { waitUntil: 'domcontentloaded' })

  const brand = page.locator('.auth-top-bar')
  const form = page.locator('.auth-right-wrap .form')
  await expect(form).toBeVisible()
  const brandBounds = await brand.boundingBox()
  const formBounds = await form.boundingBox()
  expect(brandBounds).not.toBeNull()
  expect(formBounds).not.toBeNull()
  expect(brandBounds!.y + brandBounds!.height).toBeLessThan(formBounds!.y)

  const trust = form.locator('.form__trust')
  await trust.scrollIntoViewIfNeeded()
  await expect(trust).toBeInViewport()
  await expectNoHorizontalOverflow(page)
})
