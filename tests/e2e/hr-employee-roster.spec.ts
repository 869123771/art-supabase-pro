import { expect, test, type Page } from '@playwright/test'

async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const overflow = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }))

  expect(
    overflow.scrollWidth,
    `页面产生横向溢出：scrollWidth=${overflow.scrollWidth}, clientWidth=${overflow.clientWidth}`
  ).toBeLessThanOrEqual(overflow.clientWidth + 1)
}

test('员工花名册与新增用户选人入口可用', async ({ page }) => {
  test.setTimeout(120_000)
  const pageErrors: string[] = []
  page.on('pageerror', (error) => pageErrors.push(error.message))

  await page.goto('/#/hr/personnel/employee-roster', { waitUntil: 'domcontentloaded' })
  const rosterPage = page.locator('.hr-roster-page')
  await rosterPage.waitFor({ state: 'visible', timeout: 10_000 }).catch(() => undefined)
  test.skip(
    !(await rosterPage.isVisible()),
    '当前 E2E 账号未授予员工花名册权限；请通过 E2E_EMAIL 使用 HR 管理员账号执行完整流程。'
  )
  await expect(page).not.toHaveURL(/#\/(?:auth\/)?login|#\/403/)
  await expect(rosterPage).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 60_000 })
  await expect(page.getByRole('heading', { name: '员工花名册' })).toBeVisible()
  await expect(page.getByText('人事档案按租户隔离', { exact: true })).toBeVisible()
  await expect(page.getByText('支持账号联动', { exact: true })).toBeVisible()
  await expect(page.getByText('组织导航', { exact: true })).toBeVisible()
  await expect(page.getByText('全部员工', { exact: true })).toBeVisible()
  await expectNoHorizontalOverflow(page)

  await page.getByRole('button', { name: '新增员工', exact: true }).click()
  await expect(page).toHaveURL(/#\/hr\/personnel\/employee-profile$/)
  await expect(page.locator('.hr-profile-page')).toBeVisible({ timeout: 60_000 })
  await expect(page.getByRole('heading', { name: '新增员工档案' })).toBeVisible()
  await expect(page.getByText('基础信息', { exact: true })).toBeVisible()
  await expect(page.getByText('劳动合同', { exact: false }).first()).toBeVisible()
  await expect(page.getByText('教育背景', { exact: false }).first()).toBeVisible()
  await expect(page.getByText('工作经历', { exact: false }).first()).toBeVisible()
  await expect(page.getByText('培训经历', { exact: false }).first()).toBeVisible()
  await expect(page.getByText('奖惩经历', { exact: false }).first()).toBeVisible()
  await expectNoHorizontalOverflow(page)
  await page.getByRole('button', { name: '取消', exact: true }).click()
  await expect(page).toHaveURL(/#\/hr\/personnel\/employee-roster$/)

  await page.goto('/#/system/user', { waitUntil: 'domcontentloaded' })
  await expect(page.locator('.user-page')).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 60_000 })
  await page.getByRole('button', { name: '新增用户', exact: true }).click()

  const userDialog = page.getByRole('dialog', { name: '新增用户' })
  await expect(userDialog).toBeVisible()
  await expect(userDialog.getByText('创建新的登录账号', { exact: true })).toBeVisible()
  await expect(userDialog.getByText('花名册员工', { exact: true })).toBeVisible()
  await expect(
    userDialog.getByText('选择后自动回填员工身份与联系信息；未建档人员也可直接填写账号资料。')
  ).toBeVisible()
  const employeeSelector = userDialog.locator('.art-data-select__single-input')
  await expect(employeeSelector).toHaveCount(1)
  await employeeSelector.click()

  const employeeSelectorDialog = page.getByRole('dialog', { name: '从员工花名册选择' })
  await expect(employeeSelectorDialog).toBeVisible()
  await expect(
    employeeSelectorDialog.getByText('仅展示当前租户内在岗、且尚未开通账号的员工')
  ).toBeVisible()
  await expect(employeeSelectorDialog.getByText('员工工号', { exact: true })).toBeVisible()
  await expect(employeeSelectorDialog.getByText('员工姓名', { exact: true })).toBeVisible()
  await expect(page.locator('.el-loading-mask:visible')).toHaveCount(0, { timeout: 60_000 })
  await employeeSelectorDialog.getByRole('button', { name: '取消', exact: true }).click()
  await expect(employeeSelectorDialog).toBeHidden()
  await expectNoHorizontalOverflow(page)
  await userDialog.getByRole('button', { name: '取消', exact: true }).click()

  expect(pageErrors, `页面出现未捕获错误：\n${pageErrors.join('\n')}`).toEqual([])
})
