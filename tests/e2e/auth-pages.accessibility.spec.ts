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
