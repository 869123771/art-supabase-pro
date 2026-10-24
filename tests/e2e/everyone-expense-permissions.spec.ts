import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })

for (const config of [
  {
    kind: 'payee',
    title: '收款信息',
    permission: 'FinancePayeeInformation',
    resource: 'fms_payee_information',
    number: 'payee_name'
  },
  {
    kind: 'travel',
    title: '出差申请单',
    permission: 'FinanceTravelApplication',
    resource: 'fms_travel_application',
    number: 'application_no'
  },
  {
    kind: 'loan',
    title: '借款单',
    permission: 'FinanceLoanApplication',
    resource: 'fms_travel_loan',
    number: 'loan_no'
  },
  {
    kind: 'repayment',
    title: '还款单',
    permission: 'FinanceRepayment',
    resource: 'fms_travel_repayment',
    number: 'repayment_no'
  },
  {
    kind: 'reimbursement',
    title: '费用报销单',
    permission: 'FinanceExpenseReimbursement',
    resource: 'fms_list_expense_reimbursements_secure',
    number: 'reimbursement_no'
  }
]) {
  test(`${config.title} 普通只读用户保留查询并隐藏写入动作`, async ({ page }) => {
    const writes: string[] = []
    await page.route('**/rest/v1/**', (route) => {
      const resource = new URL(route.request().url()).pathname.split('/').at(-1)
      if (route.request().method() !== 'GET' && resource !== config.resource)
        writes.push(resource || '')
      const records = [1, 2].map((index) => ({
        id: `permission-record-${index}`,
        tenant_id: '11111111-1111-4111-8111-111111111111',
        [config.number]: `QA-READONLY-${index}`,
        status: 'draft',
        source_type: 'travel',
        is_demo: true,
        attachment_urls: []
      }))
      if (resource !== config.resource) return route.fulfill({ json: [] })
      return route.fulfill({
        json: config.kind === 'reimbursement' ? { records, total: 2 } : records,
        headers: { 'content-range': '0-1/2', 'access-control-expose-headers': 'content-range' }
      })
    })
    await page.goto(
      `/tests/e2e/fixtures/receivable-workspace.html?kind=expense_${config.kind}&permissions=${config.permission}:View`
    )
    await expect(page.getByRole('heading', { name: config.title, exact: true })).toBeVisible()
    await expect(page.getByText('QA-READONLY-1', { exact: true })).toBeVisible()
    await expect(page.getByText('QA-READONLY-2', { exact: true })).toBeVisible()
    await expect(
      page.getByRole('button', {
        name: /新增|编辑|复制|删除|提交审批|模拟付款|登记付款|确认收款|一键获取员工/
      })
    ).toHaveCount(0)
    await page.getByRole('button', { name: '查询', exact: true }).click()
    await expect(page.getByText('QA-READONLY-2', { exact: true })).toBeVisible()
    expect(writes).toEqual([])
  })
}
