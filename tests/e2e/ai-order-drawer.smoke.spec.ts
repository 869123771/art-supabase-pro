import { expect, test } from '@playwright/test'

const analysisResponse = {
  artifactId: '11111111-1111-4111-8111-111111111111',
  runId: '22222222-2222-4222-8222-222222222222',
  summary: '已识别上海到杭州的电子配件运输委托，请重点核对地址和费用。',
  confidence: 0.91,
  fieldConfidence: {
    originStationName: 0.95,
    destinationStationName: 0.94,
    shippingCustomerName: 0.92,
    receivingCustomerName: 0.9,
    shippingAddressDetail: 0.58,
    receivingAddressDetail: 0.61,
    cargoItems: 0.93
  },
  missingFields: [],
  warnings: ['请在保存前确认装货时间'],
  order: {
    originStationName: 'UI验收上海发货站',
    destinationStationName: 'UI验收杭州到货站',
    deliveryMethod: 'delivery',
    shippingCustomerName: 'UI验收发货客户',
    shippingContactName: '王先生',
    shippingContactPhone: '13800138000',
    shippingAddressDetail: '上海市浦东新区验收路1号',
    receivingCustomerName: 'UI验收收货客户',
    receivingContactName: '李女士',
    receivingContactPhone: '13900139000',
    receivingAddressDetail: '浙江省杭州市余杭区验收路2号',
    cargoItems: [
      {
        cargoName: 'UI验收电子配件',
        quantity: 20,
        unit: 'box',
        weightKg: 10000,
        volumeM3: 5.5
      }
    ],
    transportFee: 15000,
    paymentMethod: 'monthly',
    transportMode: 'road'
  }
}

test('AI 智能填单采用宽屏结果优先布局并向业务角色开放一键建档', async ({ page }) => {
  test.setTimeout(300_000)
  const pageErrors: string[] = []
  page.on('pageerror', (error) => pageErrors.push(error.message))

  await page.route('**/functions/v1/ai-order-assistant', async (route) => {
    const requestBody = route.request().postDataJSON() as { action?: string } | null
    if (requestBody?.action === 'generate_example') {
      await route.fulfill({ status: 200, json: { prompt: 'AI 生成的开单示例' } })
      return
    }
    await route.fulfill({ status: 200, json: analysisResponse })
  })

  await page.goto('/#/tms-transportation/order-open', { waitUntil: 'domcontentloaded' })
  await expect(page).not.toHaveURL(/#\/auth\/login/)
  const openButton = page.getByRole('button', { name: 'AI智能填单' })
  await expect(openButton).toBeVisible({ timeout: 240_000 })
  await openButton.click()

  const drawer = page.locator('.el-drawer').filter({ hasText: 'AI 智能填单' })
  await expect(drawer).toBeVisible({ timeout: 30_000 })
  const drawerWidth = await drawer.evaluate((element) => element.getBoundingClientRect().width)
  expect(drawerWidth).toBeGreaterThanOrEqual(1200)
  await expect(drawer.getByText('三步完成智能填单', { exact: true })).toBeVisible()

  await drawer.getByRole('textbox').first().fill('上海到杭州电子配件运输委托')
  await drawer.getByRole('button', { name: '开始智能识别' }).click()

  await expect(drawer.getByText('识别完成', { exact: true })).toBeVisible({ timeout: 30_000 })
  await expect(drawer.getByText('已识别原始资料', { exact: true })).toBeVisible()
  await expect(drawer.getByRole('button', { name: /一键建档 \d+ 项/ })).toBeEnabled()

  const overflow = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }))
  expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.clientWidth + 1)
  await page.screenshot({ path: '.artifacts/ai-order-redesign-desktop.png', fullPage: true })

  await page.setViewportSize({ width: 390, height: 844 })
  await expect(drawer).toBeVisible()
  const drawerOverflow = await drawer.evaluate((element) => ({
    clientWidth: element.clientWidth,
    scrollWidth: element.scrollWidth
  }))
  expect(drawerOverflow.scrollWidth).toBeLessThanOrEqual(drawerOverflow.clientWidth + 1)
  await drawer.locator('.el-drawer__body').evaluate((element) => element.scrollTo({ top: 0 }))
  await expect(drawer.getByText('已识别原始资料', { exact: true })).toBeVisible()
  await page.screenshot({ path: '.artifacts/ai-order-redesign-mobile.png', fullPage: true })

  expect(pageErrors).toEqual([])
})
