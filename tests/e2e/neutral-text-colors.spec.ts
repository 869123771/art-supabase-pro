import { expect, test } from '@playwright/test'
import { contrast } from './text-contrast'
test('公共中性文字在主题和浅填充背景上可读', async ({ page }, info) => {
  await page.goto('/tests/e2e/fixtures/neutral-text-colors.html')
  await expect(page.locator('.neutral-text')).toHaveCount(8)
  for (const dark of [false, true])
    for (const box of ['border-mode', 'shadow-mode']) {
      await page.evaluate(
        ({ dark, box }) => {
          document.documentElement.classList.toggle('dark', dark)
          document.documentElement.dataset.boxMode = box
        },
        { dark, box }
      )
      for (const text of await page.locator('.neutral-text').all())
        expect(
          await contrast(text),
          String(dark) + ' ' + (await text.textContent())
        ).toBeGreaterThanOrEqual(4.5)
      await page.screenshot({
        path: info.outputPath((dark ? 'dark' : 'light') + '-' + box + '.png')
      })
    }
})
