import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })
test('隐藏图表可见后应用原始配置与动画偏好', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.goto('/tests/e2e/fixtures/chart-motion.html?kind=hidden')
  await expect(page.locator('[_echarts_instance_]')).toHaveCount(0)
  await page.getByRole('button', { name: '显示图表' }).click()
  const read = async () => JSON.parse((await page.getByTestId('chart-state').textContent()) || '{}')
  await expect.poll(async () => (await read()).series?.[0]?.data).toEqual([23])
  await expect.poll(async () => (await read()).animation).toBe(false)
  await page.emulateMedia({ reducedMotion: 'no-preference' })
  await expect.poll(async () => (await read()).animation).toBe(true)
})
test('延迟初始化清空后不恢复旧图表', async ({ page }) => {
  await page.clock.install()
  await page.goto('/tests/e2e/fixtures/chart-motion.html?kind=delayed')
  await page.getByRole('button', { name: '清空统计' }).click()
  await expect(page.getByText('暂无数据', { exact: true })).toBeVisible()
  await page.clock.fastForward(6000)
  await expect(page.locator('[_echarts_instance_]')).toHaveCount(0)
  await page.getByRole('button', { name: '更新统计' }).click()
  await page.clock.fastForward(6000)
  await expect(page.locator('[_echarts_instance_]')).toHaveCount(1)
  await expect(page.getByText('暂无数据', { exact: true })).toHaveCount(0)
})
for (const kind of ['line', 'bar'] as const) {
  for (const initialMotion of ['reduce', 'no-preference'] as const) {
    test(`${kind} 图表真实值与动画中断 ${initialMotion}`, async ({ page }, testInfo) => {
      const errors: string[] = []
      page.on('pageerror', (error) => errors.push(error.message))
      await page.clock.install()
      await page.emulateMedia({ reducedMotion: initialMotion })
      await page.goto(`/tests/e2e/fixtures/chart-motion.html?kind=${kind}`)
      const output = page.getByTestId('chart-state')
      const read = async () => JSON.parse((await output.textContent()) || '{}')
      if (initialMotion === 'no-preference') {
        await expect.poll(async () => (await read()).animation).toBe(true)
        await page.getByRole('button', { name: '更新统计' }).click()
        await page.emulateMedia({ reducedMotion: 'reduce' })
      }
      await expect.poll(async () => (await read()).animation).toBe(false)
      await expect
        .poll(async () =>
          (await read()).series.map((item: { animation: boolean }) => item.animation)
        )
        .toEqual([false, false])
      await expect
        .poll(async () => (await read()).series.map((item: { data: number[] }) => item.data))
        .toEqual(initialMotion === 'reduce' ? [[7], [8]] : [[23], [24]])
      await page.getByRole('button', { name: '更新统计' }).click()
      await expect
        .poll(async () => (await read()).series.map((item: { data: number[] }) => item.data))
        .toEqual([[23], [24]])
      await page.emulateMedia({ reducedMotion: 'no-preference' })
      await expect.poll(async () => (await read()).animation).toBe(true)
      await page.emulateMedia({ reducedMotion: 'reduce' })
      await expect.poll(async () => (await read()).animation).toBe(false)
      await expect
        .poll(async () => (await read()).series.map((item: { data: number[] }) => item.data))
        .toEqual([[23], [24]])
      await page.clock.fastForward(6000)
      await expect
        .poll(async () => (await read()).series.map((item: { data: number[] }) => item.data))
        .toEqual([[23], [24]])
      await page.screenshot({
        path: testInfo.outputPath('reduced-motion.png'),
        animations: 'disabled'
      })
      expect(
        await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
      ).toBeLessThanOrEqual(1)
      expect(errors).toEqual([])
      await page.getByRole('button', { name: '清空统计' }).click()
      await expect(page.getByText('暂无数据', { exact: true })).toBeVisible()
      await expect.poll(async () => (await read()).series || []).toEqual([])
      await page.emulateMedia({ reducedMotion: 'no-preference' })
      await page.clock.fastForward(6000)
      await expect.poll(async () => (await read()).series || []).toEqual([])
      await page.emulateMedia({ reducedMotion: 'reduce' })
      await page.clock.fastForward(6000)
      await expect.poll(async () => (await read()).series || []).toEqual([])
    })
  }
}
