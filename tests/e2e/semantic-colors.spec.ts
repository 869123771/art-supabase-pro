import { expect, test, type Locator } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })

async function contrast(locator: Locator): Promise<number> {
  return locator.evaluate((element) => {
    const channels = (value: string) => value.match(/[\d.]+/g)?.map(Number) ?? []
    let background = [255, 255, 255]
    const ancestors: Element[] = []
    for (let parent: Element | null = element; parent; parent = parent.parentElement) {
      ancestors.unshift(parent)
    }
    for (const ancestor of ancestors) {
      const color = channels(getComputedStyle(ancestor).backgroundColor)
      const alpha = color[3] ?? 1
      background = background.map(
        (channel, index) => (color[index] ?? 0) * alpha + channel * (1 - alpha)
      )
    }
    const foreground = channels(getComputedStyle(element).color)
    const luminance = (color: number[]) =>
      color.slice(0, 3).reduce((sum, channel, index) => {
        const value = channel / 255
        return (
          sum +
          (value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4) *
            [0.2126, 0.7152, 0.0722][index]
        )
      }, 0)
    const a = luminance(foreground)
    const b = luminance(background)
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
  })
}

test('公共语义颜色在两种主题及容器模式下可读', async ({ page }, info) => {
  await page.goto('/tests/e2e/fixtures/semantic-colors.html')
  await expect(page.getByRole('region', { name: 'success', exact: true })).toBeVisible({
    timeout: 60_000
  })
  for (const theme of ['light', 'dark']) {
    for (const box of ['border-mode', 'shadow-mode']) {
      await page.evaluate(
        ({ theme, box }) => {
          document.documentElement.classList.toggle('dark', theme === 'dark')
          document.documentElement.dataset.boxMode = box
        },
        { theme, box }
      )
      const text = page.locator('.el-tag, .el-button, .el-alert__title, .el-alert__description')
      for (const element of await text.all()) {
        expect(
          await contrast(element),
          `${theme}: ${await element.textContent()}`
        ).toBeGreaterThanOrEqual(4.5)
      }
      if (!info.project.use.isMobile) {
        for (const button of await page.locator('.el-button').all()) {
          await button.hover()
          await page.waitForTimeout(150)
          expect(
            await contrast(button),
            `${theme} hover: ${await button.textContent()}`
          ).toBeGreaterThanOrEqual(4.5)
        }
      }
      await expect
        .poll(() => page.evaluate(() => document.documentElement.scrollWidth - innerWidth))
        .toBeLessThanOrEqual(1)
      await page.screenshot({ path: info.outputPath(`${theme}-${box}.png`), fullPage: true })
    }
  }
})
