import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })

test('file preview renders an image and an expired-link state', async ({ page }, testInfo) => {
  const pageErrors: string[] = []
  page.on('pageerror', (error) => pageErrors.push(error.message))

  await page.addInitScript(() => {
    localStorage.setItem(
      'art-file-preview:sample-image',
      JSON.stringify({
        file: {
          url: `${location.origin}/data/equipment-accessory-demo/safety-valve-photo.png`,
          name: '安全阀照片.png',
          fileType: 'png'
        },
        expiresAt: Date.now() + 60_000
      })
    )
  })

  await page.goto('/#/file-preview?key=sample-image', { waitUntil: 'domcontentloaded' })
  await expect(page.locator('.art-file-viewer-page__title strong')).toHaveText('安全阀照片.png')
  await expect(page.locator('.art-file-viewer-page__body img').first()).toBeVisible()
  await expect(page.locator('.art-file-viewer-page__body')).not.toContainText('无法打开文件预览')
  await page.screenshot({ path: testInfo.outputPath('file-preview.png') })

  await page.goto('/#/file-preview?key=expired', { waitUntil: 'domcontentloaded' })
  await expect(page.getByText('无法打开文件预览')).toBeVisible()
  await expect(page.getByText('预览地址不存在或已过期，请从附件名称重新打开')).toBeVisible()
  expect(pageErrors).toEqual([])
})
