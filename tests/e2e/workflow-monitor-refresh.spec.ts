import { expect, test, type Route } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })
test.setTimeout(120_000)

test('审批监控旧回调结果不会覆盖刷新结果', async ({ page }) => {
  let initialCallback: Route | undefined
  let callbackRequests = 0
  await page.route('**/rest/v1/**', async (route) => {
    const url = route.request().url()
    if (url.endsWith('/rpc/get_workflow_callback_outbox')) {
      callbackRequests += 1
      if (callbackRequests === 1) {
        initialCallback = route
        return
      }
      await route.fulfill({
        json: {
          items: [],
          summary: { pending: 0, processing: 0, retryWait: 0, succeeded: 22, deadLetter: 0 }
        }
      })
    } else if (url.endsWith('/rpc/get_workflow_monitor_summary')) {
      await route.fulfill({
        json: {
          runningCount: 2,
          overdueCount: 0,
          approved30dCount: 1,
          rejected30dCount: 0,
          cancelled30dCount: 0,
          averageDurationHours: 1
        }
      })
    } else await route.fulfill({ json: { records: [], total: 0 } })
  })
  await page.goto('/tests/e2e/fixtures/workflow-monitor-refresh.html')
  await expect.poll(() => callbackRequests).toBe(1)
  await expect(
    page
      .locator('.workflow-monitor__callback-health')
      .getByText('正在检查回调健康度', { exact: true })
  ).toHaveCount(1)
  const refresh = page.getByRole('button', { name: '刷新审批监控数据' })
  await expect(refresh).toBeEnabled()
  await refresh.click()
  await expect.poll(() => callbackRequests).toBe(2)
  const health = page.locator('.workflow-monitor__callback-health')
  await expect(health).toContainText('22')
  await initialCallback?.fulfill({
    json: {
      items: [],
      summary: { pending: 99, processing: 0, retryWait: 99, succeeded: 1, deadLetter: 99 }
    }
  })
  const lateResponse = await initialCallback?.request().response()
  await lateResponse?.finished()
  await page.evaluate(
    () =>
      new Promise<void>((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
      )
  )
  await expect(health).toHaveAttribute('aria-busy', 'false')
  await expect(health).toContainText('22')
  await expect(health).not.toContainText('99')
  await expect(page.getByText('业务回调运行正常', { exact: true })).toBeVisible()
  await page.screenshot({
    path: `.artifacts/workflow-monitor-refresh-${page.viewportSize()?.width}.png`,
    fullPage: true
  })
})

test('回调健康度失败不显示正常状态且可重试', async ({ page }) => {
  let callbackRequests = 0
  await page.route('**/rest/v1/**', async (route) => {
    const url = route.request().url()
    if (url.endsWith('/rpc/get_workflow_callback_outbox')) {
      callbackRequests += 1
      if (callbackRequests === 1 || callbackRequests === 3) {
        await route.fulfill({ status: 500, json: { message: 'internal failure', code: 'XX000' } })
      } else
        await route.fulfill({
          json: {
            items: [],
            summary: { pending: 0, processing: 0, retryWait: 0, succeeded: 7, deadLetter: 0 }
          }
        })
    } else if (url.endsWith('/rpc/get_workflow_monitor_summary')) {
      await route.fulfill({
        json: {
          runningCount: 0,
          overdueCount: 0,
          approved30dCount: 0,
          rejected30dCount: 0,
          cancelled30dCount: 0,
          averageDurationHours: 0
        }
      })
    } else await route.fulfill({ json: { records: [], total: 0 } })
  })
  await page.goto('/tests/e2e/fixtures/workflow-monitor-refresh.html')
  const health = page.locator('.workflow-monitor__callback-health')
  await expect(health).toContainText('回调健康度暂不可用')
  await expect(health).toHaveClass(/is-attention/)
  await expect(health).not.toContainText('业务回调运行正常')
  await expect(health).not.toContainText('internal failure')
  await page.screenshot({
    path: `.artifacts/workflow-monitor-health-error-${page.viewportSize()?.width}.png`,
    fullPage: true
  })
  await health.getByRole('button', { name: '重试健康度检查' }).click()
  await expect(health).toContainText('业务回调运行正常')
  await expect(health).toContainText('已成功 7')
  await expect(health).not.toHaveClass(/is-attention/)
  await expect(health.getByRole('button', { name: '重试健康度检查' })).toHaveCount(0)
  expect(callbackRequests).toBe(2)
  await health.getByRole('button', { name: '查看回调队列' }).click()
  const drawer = page.getByRole('dialog', { name: '业务回调队列', exact: true })
  await expect(drawer).toBeVisible()
  await expect(drawer).toContainText('队列状态暂不可用')
  await expect(drawer).not.toContainText('队列运行正常')
  await expect(drawer).not.toContainText('internal failure')
  await drawer.getByRole('button', { name: '重新加载', exact: true }).click()
  await expect(drawer).toContainText('队列运行正常')
  await expect(drawer).not.toContainText('队列状态暂不可用')
  expect(callbackRequests).toBe(4)
})

test('回调队列筛选后旧查询不会覆盖最新指标', async ({ page }) => {
  let initialDrawerRequest: Route | undefined
  let callbackRequests = 0
  await page.route('**/rest/v1/**', async (route) => {
    const url = route.request().url()
    if (url.endsWith('/rpc/get_workflow_callback_outbox')) {
      const isDrawerQuery = route.request().postDataJSON()?.p_limit === 100
      if (isDrawerQuery) callbackRequests += 1
      if (isDrawerQuery && callbackRequests === 1) {
        initialDrawerRequest = route
        return
      }
      await route.fulfill({
        json: {
          items: [],
          summary: {
            pending: 0,
            processing: 0,
            retryWait: isDrawerQuery && callbackRequests === 2 ? 13 : 0,
            succeeded: 0,
            deadLetter: 0
          }
        }
      })
    } else if (url.endsWith('/rpc/get_workflow_monitor_summary')) {
      await route.fulfill({
        json: {
          runningCount: 0,
          overdueCount: 0,
          approved30dCount: 0,
          rejected30dCount: 0,
          cancelled30dCount: 0,
          averageDurationHours: 0
        }
      })
    } else await route.fulfill({ json: { records: [], total: 0 } })
  })
  await page.goto('/tests/e2e/fixtures/workflow-monitor-refresh.html')
  await page.getByRole('button', { name: '查看回调队列' }).click()
  const drawer = page.getByRole('dialog', { name: '业务回调队列', exact: true })
  await expect(drawer).toBeVisible()
  await expect.poll(() => callbackRequests).toBe(1)
  await drawer.getByRole('combobox').press('ArrowDown')
  await page.getByRole('option', { name: '全部处理中', exact: true }).click()
  await expect.poll(() => callbackRequests).toBe(2)
  await expect(drawer).toContainText('13 条待处理')
  if (!initialDrawerRequest) throw new Error('未捕获初始队列查询')
  await initialDrawerRequest.fulfill({
    json: {
      items: [],
      summary: { pending: 0, processing: 0, retryWait: 0, succeeded: 0, deadLetter: 0 }
    }
  })
  await (await initialDrawerRequest.request().response())?.finished()
  await page.evaluate(
    () =>
      new Promise<void>((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
      )
  )
  await expect(drawer).toContainText('13 条待处理')
  await expect(drawer).not.toContainText('队列运行正常')
})
