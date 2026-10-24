import { test, expect, type Page } from '@playwright/test'
import { managementReports } from '../../modules/art-supabase-tms/src/views/components/management-reports/catalog'
import { mkdir } from 'node:fs/promises'

test.use({ storageState: { cookies: [], origins: [] } })
const fixture = '/tests/e2e/fixtures/tms-management-reports.html'
const samples = [1, 2].map((i) => ({
  _key: `report-fixture-${i}`,
  group_key: `entity-${i}`,
  order_id: `order-${i}`,
  label: `测A验收00${i}`,
  count: 4,
  undispatched: 0,
  revenue: i === 1 ? 48000 : 32000,
  cost: i === 1 ? 36000 : 38000,
  fuel_cost: i === 1 ? 1000 : 1200,
  toll_cost: i === 1 ? 300 : 600,
  profit: i === 1 ? 12000 : -6000,
  margin: i === 1 ? 25 : -18.75,
  completed: 3,
  receipt: i === 1 ? 2 : 1,
  late: 1,
  order_no: `DD-验收0${i}`,
  customer: `报表验收客户${i}`,
  customer_level: i === 1 ? 'key' : null,
  receivable_currency: 'CNY',
  receivable_balance: i === 1 ? 450 : 900,
  route: `上海 → ${i === 1 ? '北京' : '广州'}`,
  plate: `测A验收00${i}`,
  driver: `报表验收司机${i}`,
  status: i === 1 ? '运输中' : '部分签收',
  planned: '2026-10-23 08:00',
  arrived: null,
  receipt_status: i === 1 ? '已上传' : '待回收',
  statement: `DZ-验收0${i}`,
  period: '2026-10-22',
  amount: i === 1 ? 12000 : 8000,
  currency: 'CNY',
  total_amount: i === 1 ? 20000 : 15000,
  invoiced_amount: i === 1 ? 20000 : 15000,
  received_amount: i === 1 ? 8000 : 6000,
  other_applied_amount: i === 1 ? 0 : 1000,
  overdue_amount: i === 1 ? 12000 : 8000,
  due_date: '2026-10-22',
  payment_term: '月结 30 天',
  document_type: '财务应收',
  waybill_no: `YD-验收0${i}`,
  days: 1,
  description: '已超过计划到达时间，尚未完成签收',
  risk_type: i === 1 ? '车辆事故' : '司机违章',
  risk_amount: i === 1 ? 1500 : 200,
  occurred: '2026-10-23 08:00',
  vehicle_no: '验收车辆' + i,
  vehicle_type: '厢式货车',
  capacity_tons: 20,
  capacity_volume: 40,
  orders: 'DD-验收0' + i,
  inspection_due: '2027-03-01',
  insurance_due: '2027-04-01',
  origin: '上海',
  destination: i === 1 ? '北京' : '广州',
  created: '2026-10-23 01:00',
  weight_tons: 10,
  volume: 20,
  exception_flag: '有异常',
  exception_type: '延误',
  stage: '到货',
  receipt_type: '电子回单',
  receipt_due: '2026-10-20 08:00',
  collected: i === 1 ? '2026-10-15 08:00' : '2026-10-22 08:00',
  receipt_timeliness: i === 1 ? '及时回收' : '逾期回收',
  archived: i === 1 ? '已上传附件' : '未归档',
  pickups: 3,
  accident: 0,
  driver_no: '验收司机' + i,
  attendance: '正常',
  on_time_count: 3,
  on_time_rate: 75,
  exception_count: 1,
  exception_rate: 25,
  rating: '待配置评分规则',
  settlement_advice: '待业务审核'
}))
const kpiSamples = [
  {
    code: 'loading',
    label: '整车装载率',
    target: '≥85%',
    actual: 50,
    unit: '%',
    completion: 58.82,
    warning: '未达标',
    note: '按运单重量 / 额定载重'
  },
  {
    code: 'empty',
    label: '空驶率',
    target: '≤10%',
    actual: null,
    unit: '%',
    completion: null,
    warning: '待核算',
    note: '缺少空驶里程'
  },
  {
    code: 'punctual',
    label: '到货准点率',
    target: '≥98%',
    actual: 100,
    unit: '%',
    completion: 102.04,
    warning: '达标',
    note: '已到货且计划完整订单'
  },
  {
    code: 'damage',
    label: '货损率',
    target: '≤0.1%',
    actual: 0.375,
    unit: '%',
    completion: 26.67,
    warning: '未达标',
    note: '已审核货损赔付 / 同批订单营收'
  },
  {
    code: 'receipt',
    label: '回单及时率',
    target: '≥95%',
    actual: 50,
    unit: '%',
    completion: 52.63,
    warning: '未达标',
    note: '签收后 7 天内回收'
  },
  {
    code: 'turnover',
    label: '应收周转天数',
    target: '≤45天',
    actual: null,
    unit: '天',
    completion: null,
    warning: '待核算',
    note: '缺少期初期末余额'
  }
].map((row, i) => ({ ...row, _key: 'kpi-' + i }))
function reportRows(slug: string) {
  const kind = (
    {
      'monthly-overview': 'month',
      'customer-profit': 'customer',
      'driver-productivity': 'driver',
      'driver-operations': 'driverops',
      'order-profit': 'order',
      'route-profit': 'route',
      'carrier-performance': 'carrier',
      'operations-kpi': 'kpi'
    } as Record<string, string>
  )[slug]
  return samples.map((row, i) => ({
    ...row,
    ...(slug === 'receipt-tracking'
      ? { receipt_status: '已回收', receipt: 1, completed: 1, late: 0 }
      : {}),
    ...(slug === 'business-risk'
      ? {
          order_id: null,
          order_no: null,
          customer: null,
          status: i === 0 ? '未处理' : '已处理',
          description: i === 0 ? '验收事故：公司承担金额待复核' : '验收违章：已登记罚款并处理'
        }
      : {}),
    label:
      kind === 'month'
        ? `2026-${i === 0 ? '09' : '10'}`
        : kind === 'customer'
          ? row.customer
          : kind === 'driver' || kind === 'driverops'
            ? row.driver
            : kind === 'order'
              ? row.order_no
              : kind === 'route'
                ? row.route
                : kind === 'carrier'
                  ? `报表验收运力${i + 1}`
                  : kind === 'kpi'
                    ? `2026-10-${22 + i}`
                    : row.plate
  }))
}
function reportResult(slug: string, keyword = '') {
  if (slug === 'operations-kpi')
    return {
      records: kpiSamples,
      total: 6,
      summary: { count: 6, available: 4, achieved: 1, pending: 2 },
      trend: []
    }
  const all = reportRows(slug)
  const rows = keyword ? all.filter((row) => JSON.stringify(row).includes(keyword)) : all
  return {
    records: rows,
    total: rows.length,
    summary: {
      count: rows.length,
      orders: rows.length * 4,
      completed: slug === 'receipt-tracking' ? rows.length : rows.length * 3,
      receipt: rows.length,
      late: slug === 'receipt-tracking' ? 0 : rows.length,
      oldest_days: 1,
      currency: 'CNY',
      currency_count: 1,
      overdue_amount: rows.reduce((sum, row) => sum + row.overdue_amount, 0),
      in_transit: 1,
      dispatch_ready: 1,
      repair: 0,
      amount: rows.reduce((sum, row) => sum + row.amount, 0),
      revenue: rows.reduce((sum, row) => sum + row.revenue, 0),
      cost: rows.reduce((sum, row) => sum + row.cost, 0),
      profit: rows.reduce((sum, row) => sum + row.profit, 0)
    },
    trend: rows.map((row) => ({
      label: row.label,
      revenue: row.revenue,
      cost: row.cost,
      count: row.count,
      completed: row.completed
    }))
  }
}
async function waitReady(page: Page, count = 2) {
  await expect(page.getByRole('textbox', { name: '关键词', exact: true })).toBeVisible()
  await expect(page.getByRole('combobox', { name: '统计日期', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: '查询', exact: true })).toBeEnabled()
  await expect(page.locator('.el-table__body tr')).toHaveCount(count)
}

test('月度总览：年累计独立查询且失败不保留旧金额', async ({ page }) => {
  const requests: { p_start: string; p_end: string; p_limit: number; p_keyword: string | null }[] =
    []
  let failYear = false
  await page.route('**/rest/v1/rpc/tms_management_report', async (route) => {
    const body = route.request().postDataJSON()
    requests.push(body)
    const yearRequest = body.p_limit === 1
    if (yearRequest && failYear) {
      await route.fulfill({ status: 500, json: { message: 'test failure' } })
      return
    }
    const data = reportResult('monthly-overview')
    await route.fulfill({
      json: yearRequest
        ? { ...data, summary: { ...data.summary, revenue: 123456, cost: null, profit: null } }
        : data
    })
  })
  await page.goto(fixture + '?report=monthly-overview&start=2025-12-01&end=2026-02-28&keyword=验收')
  await waitReady(page)
  await expect(page.getByText('本年累计 123,456 元', { exact: true })).toBeVisible()
  await expect(page.getByText('本年累计 待核算', { exact: true })).toHaveCount(2)
  const year = requests.find((request) => request.p_limit === 1)!
  const period = requests.find((request) => request.p_limit !== 1)!
  expect(year.p_start).toBe(`${period.p_end.slice(0, 4)}-01-01`)
  expect(year.p_end).toBe(period.p_end)
  expect(year.p_keyword).toBe(period.p_keyword)
  expect(year.p_start).toBe('2026-01-01')
  expect(period.p_start).toBe('2025-12-01')
  expect(year.p_keyword).toBe('验收')
  await page.screenshot({ path: '.artifacts/tms-reports/pages/monthly-ytd.png' })
  failYear = true
  await page.getByRole('button', { name: '查询', exact: true }).click()
  await expect(page.getByText('报表读取失败，请检查权限后重试', { exact: true })).toBeVisible()
  await expect(page.getByText('本年累计 123,456 元', { exact: true })).toHaveCount(0)
})
for (const report of managementReports) {
  test(report.title + '：两条数据、筛选和视觉验收', async ({ page }) => {
    // Each case covers two themes and four focus-mode transitions; allow Vite's
    // initial module compilation without relaxing subsequent interaction checks.
    test.setTimeout(120_000)
    const errors: string[] = []
    page.on('pageerror', (error) => errors.push(error.message))
    await page.route('**/rest/v1/rpc/tms_management_report', async (route) => {
      const body = route.request().postDataJSON()
      expect(body.p_report).toBe(report.slug)
      await route.fulfill({ json: reportResult(body.p_report, body.p_keyword ?? '') })
    })
    await mkdir('.artifacts/tms-reports/pages', { recursive: true })
    for (const theme of ['light', 'dark']) {
      await page.setViewportSize({ width: theme === 'light' ? 1440 : 1024, height: 900 })
      await page.goto(
        `${fixture}?report=${report.slug}&theme=${theme}&box=${theme === 'light' ? 'border-mode' : 'shadow-mode'}`
      )
      await expect(page.getByRole('heading', { name: report.title, exact: true })).toBeVisible({
        timeout: 60_000
      })
      await waitReady(page, report.slug === 'operations-kpi' ? 6 : 2)
      if (report.slug === 'receipt-tracking') {
        await expect(page.getByText('及时回收', { exact: true })).toHaveCount(1)
        await expect(page.getByText('逾期回收', { exact: true })).toHaveCount(1)
      }
      if (report.slug === 'customer-profit') {
        await expect(page.getByText('验收重点客户', { exact: true })).toBeVisible()
        await expect(page.getByText('未维护', { exact: true })).toBeVisible()
      }
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
        true
      )
      await page.screenshot({
        path: `.artifacts/tms-reports/pages/${report.slug}-${theme}.png`,
        fullPage: true
      })
      const focus = page.getByRole('switch', { name: '专注模式' })
      await page.locator('.el-switch').filter({ has: focus }).click()
      await expect(page.getByRole('heading', { name: report.title, exact: true })).not.toBeVisible()
      await expect(page.locator('.management-report-chart')).not.toBeVisible()
      await expect(page.getByRole('textbox', { name: '关键词', exact: true })).toBeVisible()
      await expect(page.getByRole('button', { name: '查询', exact: true })).toBeVisible()
      await expect(page.getByRole('combobox', { name: '每页显示条数' })).toBeVisible()
      const focusedBody = await page.locator('.el-table__body-wrapper').boundingBox()
      expect(focusedBody?.height).toBeGreaterThan(400)
      await page.screenshot({
        path: `.artifacts/tms-reports/pages/${report.slug}-${theme}-focus.png`
      })
      await page.getByRole('button', { name: '退出专注模式', exact: true }).click()
      await expect(page.getByRole('heading', { name: report.title, exact: true })).toBeVisible()
      await page.locator('.el-switch').filter({ has: focus }).click()
      await page.keyboard.press('Escape')
      await expect(page.getByRole('heading', { name: report.title, exact: true })).toBeVisible()
      await expect(page.getByRole('textbox', { name: '关键词', exact: true })).toBeVisible()
    }
    if (report.slug === 'operations-kpi') {
      await expect(page.getByText('≥85%', { exact: true })).toBeVisible()
      await expect(page.getByRole('row').filter({ hasText: '货损率' })).toContainText('0.375%')
      await expect(page.getByRole('row').filter({ hasText: '货损率' })).toContainText('未达标')
      await expect(page.getByText('待核算', { exact: true }).first()).toBeVisible()
      expect(errors).toEqual([])
      return
    }
    await page.getByRole('textbox', { name: '关键词', exact: true }).fill('验收001')
    await page.getByRole('button', { name: '查询', exact: true }).click()
    await expect(page.locator('.el-table__body tr')).toHaveCount(1)
    await page.getByRole('button', { name: '重置', exact: true }).click()
    await waitReady(page)
    expect(errors).toEqual([])
  })
}
test('经营风险逾期金额与币种列示', async ({ page }) => {
  await page.route('**/rest/v1/rpc/tms_management_report', async (route) => {
    const response = reportResult('business-risk')
    await route.fulfill({
      json: {
        ...response,
        records: response.records.map((row, i) => ({
          ...row,
          risk_type: '应收逾期',
          plate: null,
          driver: null,
          customer: `运输应收验收客户${i + 1}`,
          risk_amount: i === 0 ? 450 : 900,
          currency: i === 0 ? 'CNY' : 'USD',
          status: '逾期未结',
          occurred: '2026-10-22',
          description: `应收单 TEST-AR-${i + 1}；到期日 2026-10-22；逾期 1 天`
        }))
      }
    })
  })
  await page.setViewportSize({ width: 1920, height: 900 })
  await page.goto(`${fixture}?report=business-risk`)
  await waitReady(page)
  await expect(page.getByText('CNY', { exact: true })).toBeVisible()
  await expect(page.getByText('USD', { exact: true })).toBeVisible()
  await expect(page.getByText('逾期未结', { exact: true })).toHaveCount(2)
  await expect(page.getByText('450', { exact: true })).toBeVisible()
  await expect(page.getByText('900', { exact: true })).toBeVisible()
  await page.screenshot({
    path: '.artifacts/tms-reports/pages/receivable-risk.png',
    fullPage: true
  })
})
test('月度 → 客户 → 订单 → 车辆穿透及筛选保留', async ({ page }) => {
  const requests: Array<{
    p_report: string
    p_keyword: string | null
    p_start: string
    p_end: string
  }> = []
  await page.route('**/rest/v1/rpc/tms_management_report', async (route) => {
    const body = route.request().postDataJSON()
    requests.push(body)
    await route.fulfill({ json: reportResult(body.p_report, body.p_keyword ?? '') })
  })
  await page.goto(fixture)
  await waitReady(page)
  await page.getByRole('textbox', { name: '关键词', exact: true }).fill('尚未查询的关键词')
  await page.getByRole('link', { name: '2026-10', exact: true }).click()
  await expect(page.getByRole('heading', { name: '客户毛利分析', exact: true })).toBeVisible()
  await waitReady(page)
  expect(requests.at(-1)?.p_start).toBe('2026-10-01')
  expect(requests.at(-1)?.p_keyword).toBeNull()
  await page.getByPlaceholder('开始日期', { exact: true }).fill('2026-10-10')
  await page.getByPlaceholder('开始日期', { exact: true }).press('Tab')
  await expect(page.getByPlaceholder('开始日期', { exact: true })).toHaveValue('2026-10-10')
  await page.getByRole('link', { name: '报表验收客户1', exact: true }).click()
  await expect(page.getByRole('heading', { name: '订单毛利分析', exact: true })).toBeVisible()
  await expect(page.locator('.el-table__body tr')).toHaveCount(1)
  expect(requests.at(-1)?.p_keyword).toBe('报表验收客户1')
  expect(requests.at(-1)?.p_start).toBe('2026-10-01')
  await page.getByRole('link', { name: '测A验收001', exact: true }).click()
  await expect(page.getByRole('heading', { name: '单车盈亏分析', exact: true })).toBeVisible()
  await expect(page.locator('.el-table__body tr')).toHaveCount(1)
  expect(requests.at(-1)?.p_keyword).toBe('测A验收001')
})
test('空态、延迟加载、失败重试、专注模式', async ({ page }) => {
  let state = 'loaded'
  let unblock: (() => void) | undefined
  let loadingGate = Promise.resolve()
  let waitingRequests = 0
  await page.route('**/rest/v1/rpc/tms_management_report', async (route) => {
    if (state === 'loading') {
      waitingRequests++
      await loadingGate
    }
    if (state === 'error') return route.fulfill({ status: 500, json: { message: 'test failure' } })
    const data = reportResult('monthly-overview')
    if (state === 'empty') Object.assign(data, { records: [], total: 0, trend: [] })
    await route.fulfill({ json: data })
  })
  await page.goto(fixture)
  await waitReady(page)
  const focus = page.getByRole('switch', { name: '专注模式' })
  await page.locator('.el-switch').filter({ has: focus }).click()
  await expect(
    page.getByRole('heading', { name: '月度经营总览看板', exact: true })
  ).not.toBeVisible()
  await page.getByRole('button', { name: '退出专注模式', exact: true }).click()
  await expect(page.getByRole('heading', { name: '月度经营总览看板', exact: true })).toBeVisible()
  await page.locator('.el-switch').filter({ has: focus }).click()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('heading', { name: '月度经营总览看板', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: '全屏查看', exact: true })).toHaveCount(0)
  state = 'loading'
  loadingGate = new Promise<void>((resolve) => {
    unblock = resolve
  })
  await page.getByRole('button', { name: '查询', exact: true }).click()
  await expect(page.getByRole('button', { name: '查询', exact: true })).toBeDisabled()
  await expect.poll(() => waitingRequests).toBe(2)
  expect(unblock).toBeDefined()
  state = 'loaded'
  unblock?.()
  await waitReady(page)
  state = 'empty'
  await page.getByRole('button', { name: '查询', exact: true }).click()
  await expect(page.getByText('暂无符合条件的报表数据', { exact: true })).toBeVisible()
  state = 'error'
  await page.getByRole('button', { name: '查询', exact: true }).click()
  await expect(
    page.getByText('报表读取失败，请检查权限后重试', { exact: true }).first()
  ).toBeVisible()
  state = 'loaded'
  await page.getByRole('button', { name: '重新加载', exact: true }).first().click()
  await waitReady(page)
})

// Verify dense content, not only two-row empty space, against the user's layout complaint.
test('图表保留可读营收，未知成本留空且不冒充零', async ({ page }) => {
  let allUnknown = false
  await page.route('**/rest/v1/rpc/tms_management_report', async (route) => {
    const result = reportResult('monthly-overview')
    await route.fulfill({
      json: {
        ...result,
        records: result.records.map((row) => ({ ...row, cost: null, profit: null, margin: null })),
        summary: {
          ...result.summary,
          revenue: allUnknown ? null : 80000,
          cost: null,
          profit: null
        },
        trend: result.trend.map((point) => ({
          ...point,
          revenue: allUnknown ? null : point.revenue,
          cost: null
        }))
      }
    })
  })
  await page.goto(fixture + '?report=monthly-overview')
  await waitReady(page)
  await expect(
    page.getByRole('img', { name: /2026-09：营收 48,000 元，已归集成本 待核算/ })
  ).toBeVisible()
  await expect(
    page.getByText('部分数值尚未核算或无权查看，图中保留空缺，不按零值计算。')
  ).toBeVisible()
  await page.screenshot({ path: '.artifacts/tms-reports/pages/partial-financial-chart.png' })
  allUnknown = true
  await page.getByRole('button', { name: '查询', exact: true }).click()
  await expect(page.getByText('暂无可展示的统计', { exact: true })).toBeVisible()
  await expect(page.locator('.management-report-chart [role="img"]')).toHaveCount(0)
})

test('单车费用明细横向查看保留车牌', async ({ page }) => {
  await page.route('**/rest/v1/rpc/tms_management_report', (route) =>
    route.fulfill({ json: reportResult('vehicle-profit') })
  )
  await page.goto(fixture + '?report=vehicle-profit')
  await waitReady(page)
  await page.locator('.el-table__body-wrapper .el-scrollbar__wrap').evaluate((element) => {
    element.scrollLeft = element.scrollWidth
  })
  await expect(
    page.getByRole('columnheader', { name: '已归集油费（元）', exact: true })
  ).toBeVisible()
  await expect(page.getByRole('cell', { name: '1,200', exact: true })).toBeVisible()
  await expect(page.getByRole('link', { name: '测A验收002', exact: true })).toBeVisible()
  await page.screenshot({ path: '.artifacts/tms-reports/pages/vehicle-cost-breakdown.png' })
})

test('外包运力已关联投诉与未知权限展示', async ({ page }) => {
  await page.route('**/rest/v1/rpc/tms_management_report', async (route) => {
    const result = reportResult('carrier-performance')
    await route.fulfill({
      json: {
        ...result,
        records: result.records.map((row, i) => ({ ...row, complaints: i === 0 ? 2 : null }))
      }
    })
  })
  await page.goto(fixture + '?report=carrier-performance')
  await waitReady(page)
  await page.locator('.el-table__body-wrapper .el-scrollbar__wrap').evaluate((element) => {
    element.scrollLeft = element.scrollWidth
  })
  await expect(
    page.getByRole('columnheader', { name: '已关联投诉次数', exact: true })
  ).toBeVisible()
  const cells = page.locator('.el-table__body tr').first().getByRole('cell')
  await expect(cells.nth(12)).toHaveText('2')
  await expect(page.locator('.el-table__body tr').nth(1).getByRole('cell').nth(12)).toHaveText(
    '待核算'
  )
  await page.screenshot({ path: '.artifacts/tms-reports/pages/carrier-complaints.png' })
})

test('外包运力评分等级及缺数据状态', async ({ page }) => {
  let missing = false
  await page.route('**/rest/v1/rpc/tms_management_report', async (route) => {
    const result = reportResult('carrier-performance')
    await route.fulfill({
      json: {
        ...result,
        records: result.records.map((row, i) => ({
          ...row,
          receipt_rate: i === 0 ? 100 : 0,
          on_time_rate: i === 0 ? 100 : 0,
          exception_rate: i === 0 ? 0 : 100,
          complaints: missing ? null : 0,
          score: missing ? null : i === 0 ? 100 : 10,
          rating: missing ? '待核算' : i === 0 ? 'A' : 'D',
          settlement_advice: missing
            ? '补齐数据后考核'
            : i === 0
              ? '优先合作，按约结算'
              : '建议整改后评估新增业务'
        }))
      }
    })
  })
  await page.goto(fixture + '?report=carrier-performance')
  await waitReady(page)
  await page.locator('.el-table__body-wrapper .el-scrollbar__wrap').evaluate((element) => {
    element.scrollLeft = element.scrollWidth
  })
  const rows = page.locator('.el-table__body tr')
  await expect(rows.first().getByRole('cell').nth(13)).toHaveText('100')
  await expect(rows.first().getByRole('cell').nth(14)).toHaveText('A')
  await expect(rows.nth(1).getByRole('cell').nth(13)).toHaveText('10')
  await expect(rows.nth(1).getByRole('cell').nth(14)).toHaveText('D')
  await page.screenshot({ path: '.artifacts/tms-reports/pages/carrier-score.png' })
  missing = true
  await page.getByRole('button', { name: '查询', exact: true }).click()
  await expect(rows.first().getByRole('cell').nth(13)).toHaveText('待核算')
  await expect(rows.first().getByRole('cell').nth(14)).toHaveText('待核算')
})

test('司机薪酬已审核月份与缺失金额展示', async ({ page }) => {
  await page.route('**/rest/v1/rpc/tms_management_report', async (route) => {
    const result = reportResult('driver-productivity')
    await route.fulfill({
      json: {
        ...result,
        records: result.records.map((row, i) => ({
          ...row,
          payroll_months: i === 0 ? '2026-09' : null,
          payroll_currency: i === 0 ? 'CNY' : null,
          payroll_gross: i === 0 ? 8000 : null,
          payroll_deductions: i === 0 ? 200 : null,
          payroll_employer: i === 0 ? 1200 : null,
          payroll_net: i === 0 ? 7800 : null
        }))
      }
    })
  })
  await page.goto(fixture + '?report=driver-productivity')
  await waitReady(page)
  await page.locator('.el-table__body-wrapper .el-scrollbar__wrap').evaluate((element) => {
    element.scrollLeft = element.scrollWidth
  })
  const rows = page.locator('.el-table__body tr')
  await expect(rows.first().getByRole('cell').nth(12)).toHaveText('8,000')
  await expect(rows.first().getByRole('cell').nth(15)).toHaveText('7,800')
  await expect(rows.nth(1).getByRole('cell').nth(12)).toHaveText('待核算')
  await expect(page.getByRole('link', { name: '报表验收司机1', exact: true })).toBeVisible()
  await page.screenshot({ path: '.artifacts/tms-reports/pages/driver-payroll.png' })
})

test('车辆薪酬分摊、保险摊销与调整后金额横向展示', async ({ page }) => {
  await page.route('**/rest/v1/rpc/tms_management_report', async (route) => {
    const result = reportResult('vehicle-profit')
    await route.fulfill({
      json: {
        ...result,
        records: result.records.map((row, i) => ({
          ...row,
          allocated_payroll: i === 0 ? 9200 : 10300,
          allocation_basis: i === 0 ? '里程' : '订单数',
          cost_with_payroll: row.cost + (i === 0 ? 9200 : 10300),
          profit_after_payroll: row.profit - (i === 0 ? 9200 : 10300),
          insurance_period_cost: i === 0 ? 330 : 660
        }))
      }
    })
  })
  await page.goto(fixture + '?report=vehicle-profit')
  await waitReady(page)
  await page.locator('.el-table__body-wrapper .el-scrollbar__wrap').evaluate((element) => {
    element.scrollLeft = element.scrollWidth
  })
  await expect(page.getByRole('cell', { name: '9,200', exact: true })).toBeVisible()
  await expect(page.getByRole('cell', { name: '45,200', exact: true })).toBeVisible()
  await expect(page.getByRole('cell', { name: '订单数', exact: true })).toBeVisible()
  await expect(page.getByRole('columnheader', { name: '期间保险摊销（元）' })).toBeVisible()
  await expect(page.getByRole('cell', { name: '330', exact: true })).toBeVisible()
  await expect(page.getByRole('cell', { name: '660', exact: true })).toBeVisible()
  await expect(page.getByRole('link', { name: '测A验收001', exact: true })).toBeVisible()
  await page.screenshot({ path: '.artifacts/tms-reports/pages/vehicle-payroll-allocation.png' })
})

test('六个经营维度展示保险分摊金额与依据', async ({ page }) => {
  test.setTimeout(120_000)
  await page.route('**/rest/v1/rpc/tms_management_report', async (route) => {
    const body = route.request().postDataJSON()
    const result = reportResult(body.p_report)
    await route.fulfill({
      json: {
        ...result,
        records: result.records.map((row, index) => ({
          ...row,
          allocated_insurance: index === 0 ? 330 : null,
          insurance_allocation_basis: index === 0 ? '里程' : '订单数'
        }))
      }
    })
  })
  for (const slug of [
    'monthly-overview',
    'vehicle-profit',
    'driver-productivity',
    'order-profit',
    'route-profit',
    'customer-profit'
  ]) {
    await page.goto(`${fixture}?report=${slug}&start=2026-09-01&end=2026-09-30`)
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 60_000 })
    await waitReady(page)
    const header = page.getByRole('columnheader', { name: '分摊保险（元）', exact: true })
    await page.locator('.el-table__body-wrapper .el-scrollbar__wrap').evaluate((element) => {
      element.scrollLeft = element.scrollWidth
    })
    await expect(header).toBeVisible()
    const headers = await page.getByRole('columnheader').allTextContents()
    const index = headers.findIndex((value) => value.includes('分摊保险（元）'))
    await expect(
      page.locator('.el-table__body tr').first().getByRole('cell').nth(index)
    ).toHaveText('330')
    await expect(page.locator('.el-table__body tr').nth(1).getByRole('cell').nth(index)).toHaveText(
      '待核算'
    )
    await expect(
      page.getByRole('columnheader', { name: '保险分摊依据', exact: true })
    ).toBeVisible()
    await page.screenshot({ path: `.artifacts/tms-reports/pages/${slug}-insurance-allocation.png` })
  }
})

test('客户毛利已关联投诉横向查看', async ({ page }) => {
  await page.route('**/rest/v1/rpc/tms_management_report', async (route) => {
    const result = reportResult('customer-profit')
    await route.fulfill({
      json: {
        ...result,
        records: result.records.map((row, i) => ({ ...row, complaints: i === 0 ? 1 : null }))
      }
    })
  })
  await page.goto(fixture + '?report=customer-profit')
  await waitReady(page)
  await page.locator('.el-table__body-wrapper .el-scrollbar__wrap').evaluate((element) => {
    element.scrollLeft = element.scrollWidth
  })
  await expect(
    page.getByRole('columnheader', { name: '已关联投诉次数', exact: true })
  ).toBeVisible()
  await expect(page.locator('.el-table__body tr').first().getByRole('cell').nth(10)).toHaveText('1')
  await expect(page.locator('.el-table__body tr').nth(1).getByRole('cell').nth(10)).toHaveText(
    '待核算'
  )
  await expect(page.getByRole('link', { name: '报表验收客户1', exact: true })).toBeVisible()
  await page.screenshot({ path: '.artifacts/tms-reports/pages/customer-complaints.png' })
})

test('客户应收余额与多币种提示', async ({ page }) => {
  await page.route('**/rest/v1/rpc/tms_management_report', async (route) => {
    const result = reportResult('customer-profit')
    await route.fulfill({
      json: {
        ...result,
        records: result.records.map((row, i) => ({
          ...row,
          receivable_currency: i === 0 ? 'CNY' : '多币种，分币种查看',
          receivable_balance: i === 0 ? 450 : null,
          overdue_amount: i === 0 ? 450 : null
        }))
      }
    })
  })
  await page.goto(fixture + '?report=customer-profit')
  await waitReady(page)
  await page.locator('.el-table__body-wrapper .el-scrollbar__wrap').evaluate((element) => {
    element.scrollLeft = element.scrollWidth
  })
  await expect(
    page.getByRole('columnheader', { name: '期间应收未核销余额', exact: true })
  ).toBeVisible()
  await expect(page.getByText('多币种，分币种查看', { exact: true })).toBeVisible()
  await expect(page.locator('.el-table__body tr').first().getByRole('cell').last()).toHaveText(
    '450'
  )
  await expect(page.locator('.el-table__body tr').nth(1).getByRole('cell').last()).toHaveText(
    '待核算'
  )
  await page.screenshot({ path: '.artifacts/tms-reports/pages/customer-receivables.png' })
})

test('线路单位收支与未知成本横向查看', async ({ page }) => {
  await page.route('**/rest/v1/rpc/tms_management_report', async (route) => {
    const result = reportResult('route-profit')
    const records = result.records.map((row, i) => ({
      ...row,
      unit_revenue: i === 0 ? 1200 : null,
      unit_cost: i === 0 ? 900 : null
    }))
    await route.fulfill({ json: { ...result, records } })
  })
  await page.goto(fixture + '?report=route-profit')
  await waitReady(page)
  await page.locator('.el-table__body-wrapper .el-scrollbar__wrap').evaluate((element) => {
    element.scrollLeft = element.scrollWidth
  })
  await expect(
    page.getByRole('columnheader', { name: '单位收入（元/吨）', exact: true })
  ).toBeVisible()
  await expect(page.getByRole('cell', { name: '1,200', exact: true })).toBeVisible()
  await expect(page.getByRole('cell', { name: '900', exact: true })).toBeVisible()
  await expect(page.getByRole('cell', { name: '待核算', exact: true })).toHaveCount(2)
  await expect(page.getByRole('link', { name: '上海 → 北京', exact: true })).toBeVisible()
  await page.screenshot({ path: '.artifacts/tms-reports/pages/route-unit-economics.png' })
})

test('紧凑查询、图表与长表格空间分配', async ({ page }) => {
  await page.route('**/rest/v1/rpc/tms_management_report', async (route) => {
    const result = reportResult('vehicle-profit')
    const records = Array.from({ length: 20 }, (_, i) => ({
      ...samples[i % 2],
      _key: 'dense-' + i,
      label: '测A验收' + String(i + 1).padStart(3, '0')
    }))
    await route.fulfill({ json: { ...result, records, total: 20 } })
  })
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.goto(fixture + '?report=vehicle-profit')
  await waitReady(page, 20)
  const date = await page.locator('.art-search-bar .el-date-editor').boundingBox()
  const keyword = await page.getByRole('textbox', { name: '关键词', exact: true }).boundingBox()
  const query = await page.getByRole('button', { name: '查询', exact: true }).boundingBox()
  expect(date).not.toBeNull()
  expect(keyword).not.toBeNull()
  expect(query).not.toBeNull()
  expect(Math.abs(date!.y - query!.y)).toBeLessThan(8)
  expect(Math.abs(keyword!.y - query!.y)).toBeLessThan(8)
  expect(date!.width).toBeLessThanOrEqual(380)
  expect(keyword!.width).toBeLessThanOrEqual(300)
  const chart = await page.locator('.management-report-chart').boundingBox()
  expect(chart!.height).toBeLessThanOrEqual(200)
  const body = await page.locator('.el-table__body-wrapper').boundingBox()
  expect(body!.height).toBeGreaterThan(250)
  expect(body!.y + body!.height).toBeLessThan(850)
  await expect(page.getByRole('button', { name: '全屏查看', exact: true })).toHaveCount(0)
  await page.screenshot({
    path: '.artifacts/tms-reports/pages/dense-layout-1440.png',
    fullPage: true
  })
  await page.setViewportSize({ width: 640, height: 900 })
  await expect(page.getByRole('button', { name: '查询', exact: true })).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  await page.screenshot({
    path: '.artifacts/tms-reports/pages/dense-layout-640.png',
    fullPage: true
  })
})
