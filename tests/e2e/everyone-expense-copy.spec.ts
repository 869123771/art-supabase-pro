import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })
test.setTimeout(120000)

for (const config of [
  {
    kind: 'payee',
    resource: 'fms_payee_information',
    number: 'payee_name',
    copy: '复制',
    save: 'fms_payee_information'
  },
  {
    kind: 'travel',
    resource: 'fms_travel_application',
    number: 'application_no',
    copy: '复制出差申请',
    save: 'copy_fms_travel_application_draft_secure'
  },
  {
    kind: 'loan',
    resource: 'fms_travel_loan',
    number: 'loan_no',
    copy: '复制借款单',
    save: 'copy_fms_travel_loan_draft_secure'
  },
  {
    kind: 'repayment',
    resource: 'fms_travel_repayment',
    number: 'repayment_no',
    copy: '复制还款单',
    save: 'save_fms_travel_repayment_draft_entry_secure'
  },
  {
    kind: 'reimbursement',
    resource: 'fms_list_expense_reimbursements_secure',
    number: 'reimbursement_no',
    copy: '复制',
    save: 'fms_save_travel_reimbursement_draft_secure'
  }
]) {
  test(`${config.kind} 两张来源单复制为独立草稿并保留组织`, async ({ page }, info) => {
    const tenant = '11111111-1111-4111-8111-111111111111'
    const saved: Record<string, unknown>[] = []
    const loan = {
      id: 'source-loan',
      tenant_id: tenant,
      loan_no: 'JK-COPY-SOURCE',
      applicant_employee_id: 'employee',
      applicant_name: '验收员工',
      expense_department_id: 'department',
      expense_department_name: '验收部门',
      remaining_balance: 500,
      available_amount: 500,
      items: [
        {
          id: 'source-loan-item',
          amount: 500,
          purpose: '原借款事项',
          expense_item_name: '验收项目',
          currency_code: 'CNY',
          exchange_rate: 1
        }
      ]
    }
    const records = [1, 2].map((index) => ({
      id: `copy-source-${index}`,
      tenant_id: tenant,
      [config.number]: `QA-COPY-${index}`,
      status: config.kind === 'repayment' ? 'draft' : 'approved',
      source_type: 'travel',
      is_demo: true,
      is_employee: false,
      is_default: true,
      authorized_use: false,
      payee_name: `QA-COPY-${index}`,
      bank_name: '验收银行',
      bank_account: `622200000000000${index}`,
      currency_code: 'CNY',
      organization_id: 'department',
      cost_company_id: 'company',
      applicant_employee_id: 'employee',
      applicant_name: '验收员工',
      applicant_name_snapshot: '验收员工',
      applicant_employee_no: 'QA001',
      applicant_organization_id: 'department',
      assignment_id: 'assignment',
      expense_department_id: 'department',
      expense_department_name: '验收部门',
      application_date: '2026-10-01',
      reimbursement_date: '2026-10-01',
      repayment_date: '2026-10-20',
      travel_type: 'domestic',
      multiple_travelers: false,
      multiple_reimbursees: false,
      reason: `复制验收事由${index}`,
      remark: '原单备注',
      attachment_urls: [],
      basis_urls: [],
      requested_amount: 100,
      loan_amount: 100,
      total_amount: 100,
      amount: 100,
      approved_amount: 100,
      paid_amount: 100,
      received_amount: 100,
      travel_loan_id: config.kind === 'reimbursement' ? 'previous-loan' : undefined,
      loan_offset_amount: 0,
      cash_payable_amount: 100,
      loan_id: 'source-loan',
      loan: config.kind === 'repayment' ? loan : undefined,
      payments: [{ id: 'old-payment', amount: 100 }],
      receipts: [],
      itineraries: [
        {
          id: `old-line-${index}`,
          departure_place: '验收出发地',
          departure_region_path: [],
          destination_place: '验收目的地',
          destination_region_path: [],
          start_date: '2026-10-24',
          end_date: '2026-10-25',
          transport_modes: [],
          traveler_employee_ids: [],
          expense_item_id: 'expense',
          requested_amount: 100
        }
      ],
      items: [
        {
          id: `old-line-${index}`,
          expense_item_id: 'expense',
          purpose: '验收借款用途',
          borrower_employee_id: 'employee',
          loan_item_id: 'source-loan-item',
          amount: 100,
          remark: null
        }
      ],
      travel_lines: [
        {
          id: `old-line-${index}`,
          expense_item_id: 'expense',
          expense_item_name_snapshot: '验收项目',
          occurred_on: '2026-10-23',
          gross_amount: 100,
          tax_amount: 0,
          tax_rate: 0
        }
      ],
      payees: [
        {
          id: `old-payee-${index}`,
          settlement_method: 'bank_transfer',
          payee_type: 'person',
          payee_information_id: 'payee',
          payee_name: '验收收款人',
          payee_name_snapshot: '验收收款人',
          bank_name: '验收银行',
          bank_name_snapshot: '验收银行',
          bank_account: '6222000000000001',
          bank_account_snapshot: '6222000000000001',
          amount: 100
        }
      ]
    }))
    await page.route('**/rest/v1/**', (route) => {
      const url = new URL(route.request().url())
      const resource = url.pathname.split('/').at(-1)
      if (resource === config.save && route.request().method() === 'POST') {
        const payload = route.request().postDataJSON() as Record<string, unknown>
        saved.push(payload)
        return route.fulfill({
          json: { id: `new-copy-${saved.length}`, status: 'draft', ...payload }
        })
      }
      if (resource === 'mdm_organization')
        return route.fulfill({
          json: [
            {
              id: 'company',
              tenant_id: tenant,
              organization_name: '验收公司',
              organization_code: 'C',
              organization_type: 'company',
              parent_id: null,
              status: '1'
            },
            {
              id: 'department',
              tenant_id: tenant,
              organization_name: '验收部门',
              organization_code: 'D',
              organization_type: 'department',
              parent_id: 'company',
              status: '1'
            }
          ]
        })
      if (resource === 'mdm_employee')
        return route.fulfill({
          json: [
            {
              id: 'employee',
              tenant_id: tenant,
              employee_name: '验收员工',
              employee_no: 'QA001',
              organization_id: 'department'
            }
          ]
        })
      if (resource === 'mdm_employee_assignment')
        return route.fulfill({
          json: [{ id: 'assignment', business_title: '验收职位', primary_assignment: true }]
        })
      if (resource === 'tms_expense_item')
        return route.fulfill({ json: [{ id: 'expense', item_name: '验收项目', is_enabled: true }] })
      if (resource === 'fms_list_repayable_loans_secure') return route.fulfill({ json: [loan] })
      if (resource === 'fms_travel_loan' && config.kind === 'repayment')
        return route.fulfill({ json: loan })
      if (resource === 'tms_get_expense_reimbursement_secure')
        return route.fulfill({
          json: records.find((record) => record.id === route.request().postDataJSON().p_id)
        })
      if (resource !== config.resource) return route.fulfill({ json: [] })
      const id = url.searchParams.get('id')?.replace(/^eq\./, '')
      if (id) return route.fulfill({ json: records.find((record) => record.id === id) })
      return route.fulfill({
        json: config.kind === 'reimbursement' ? { records, total: 2 } : records,
        headers: { 'content-range': '0-1/2', 'access-control-expose-headers': 'content-range' }
      })
    })
    await page.goto(`/tests/e2e/fixtures/receivable-workspace.html?kind=expense_${config.kind}`)
    for (const index of [1, 2]) {
      const row = page.getByRole('row').filter({ hasText: `QA-COPY-${index}` })
      await expect(row).toBeVisible()
      if (config.kind === 'payee') {
        await row.getByRole('button', { name: '更多操作', exact: true }).click()
        await page.getByRole('menuitem', { name: config.copy, exact: true }).click()
      } else await row.getByRole('button', { name: config.copy, exact: true }).click()
      const dialog = page
        .getByRole('dialog')
        .filter({ hasText: config.kind === 'payee' ? '复制收款信息' : '保存草稿' })
      await expect(dialog).toBeVisible()
      if (config.kind !== 'payee') {
        const reason = dialog.getByRole('textbox', { name: /事由$/ })
        await expect(reason).toHaveValue(`复制验收事由${index}`)
        await reason.fill(`新草稿事由${index}`)
      }
      if (index === 2)
        await page.screenshot({ path: info.outputPath(`${config.kind}-copy.png`), fullPage: true })
      await dialog
        .getByRole('button', {
          name: config.kind === 'payee' ? '保存收款信息' : '保存草稿',
          exact: true
        })
        .click()
      await expect(dialog).not.toBeVisible()
    }
    expect(saved).toHaveLength(2)
    for (const [index, body] of saved.entries()) {
      const payload = config.kind === 'payee' ? body : (body.p_payload as Record<string, unknown>)
      expect(payload.id).toBeUndefined()
      expect(payload.tenant_id).toBe(tenant)
      for (const key of [
        'status',
        'approved_amount',
        'paid_amount',
        'received_amount',
        'payments',
        'receipts'
      ])
        expect(payload).not.toHaveProperty(key)
      if (config.kind === 'payee') expect(payload.is_default).toBe(false)
      else {
        expect(payload.reason).toBe(`新草稿事由${index + 1}`)
        expect(payload.expense_department_id ?? payload.loan_id).toBe(
          config.kind === 'repayment' ? 'source-loan' : 'department'
        )
      }
      if (config.kind === 'travel' || config.kind === 'loan')
        expect(body.p_source_id).toBe(`copy-source-${index + 1}`)
      if (config.kind === 'reimbursement') {
        expect(payload.travel_loan_id).toBeNull()
        expect(payload.loan_offset_amount).toBe(0)
      }
      for (const key of ['p_lines', 'p_items', 'p_payees']) {
        const lines = body[key] as Record<string, unknown>[] | undefined
        if (lines) for (const line of lines) expect(line.id).toBeUndefined()
      }
    }
  })
}
